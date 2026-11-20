import os, json, datetime, threading, logging
from fastapi import FastAPI, Header, HTTPException, Response
from pydantic import BaseModel, conint
from azure.identity import DefaultAzureCredential
from azure.data.tables import TableServiceClient
from azure.core.exceptions import ResourceExistsError, ResourceNotFoundError
from azure.servicebus import ServiceBusClient, ServiceBusMessage

logging.basicConfig(level=logging.INFO)               # console + root level first
logging.getLogger("azure").setLevel(logging.WARNING)  # keep SDK noise out
if os.getenv("APPLICATIONINSIGHTS_CONNECTION_STRING"):
    from azure.monitor.opentelemetry import configure_azure_monitor
    configure_azure_monitor()

cred = DefaultAzureCredential()
orders = TableServiceClient(endpoint=os.environ["TABLES_ENDPOINT"], credential=cred).get_table_client("orders")
sb = ServiceBusClient(os.environ["SB_FQDN"], cred)
sender = sb.get_topic_sender("orders")      # opened once, reused for every order
send_lock = threading.Lock()                # a sender isn't thread-safe; FastAPI runs handlers in threads
GATEWAY_SECRET = os.getenv("GATEWAY_SECRET")

app = FastAPI(title="order-api", version="2.0")

class Line(BaseModel):
    sku: str
    qty: conint(gt=0)

class Order(BaseModel):
    storeId: str
    channel: str
    lines: list[Line]

def check_gateway(secret):
    if GATEWAY_SECRET and secret != GATEWAY_SECRET:
        raise HTTPException(401, "call through the API gateway")

def to_order(e):
    return {"orderId": e["RowKey"], "status": e["status"], "storeId": e["storeId"],
            "channel": e["channel"], "lines": json.loads(e["lines"]), "createdAt": e["createdAt"]}

@app.get("/healthz")
def health():
    return {"status": "ok"}

@app.post("/orders", status_code=201)
def place_order(order: Order, response: Response, idempotency_key: str = Header(...),
                x_gateway_secret: str | None = Header(None)):
    check_gateway(x_gateway_secret)
    if any(c in idempotency_key for c in "/\\#?"):
        raise HTTPException(400, "invalid Idempotency-Key")
    entity = {"PartitionKey": idempotency_key, "RowKey": idempotency_key, "status": "PLACED",
              "storeId": order.storeId, "channel": order.channel,
              "lines": json.dumps([l.model_dump() for l in order.lines]),
              "createdAt": datetime.datetime.utcnow().isoformat() + "Z"}
    try:
        orders.create_entity(entity)
    except ResourceExistsError:
        response.status_code = 200
        return to_order(orders.get_entity(idempotency_key, idempotency_key))
    doc = to_order(entity)
    with send_lock:
        sender.send_messages(ServiceBusMessage(
            json.dumps(doc), message_id=idempotency_key, subject="OrderPlaced",
            application_properties={"channel": order.channel, "storeId": order.storeId}))
    return doc

@app.get("/orders/{order_id}")
def get_order(order_id: str, x_gateway_secret: str | None = Header(None)):
    check_gateway(x_gateway_secret)
    try:
        return to_order(orders.get_entity(order_id, order_id))
    except ResourceNotFoundError:
        raise HTTPException(404)
