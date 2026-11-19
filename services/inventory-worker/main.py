import os, json, logging
from azure.identity import DefaultAzureCredential
from azure.data.tables import TableServiceClient, UpdateMode
from azure.core import MatchConditions
from azure.core.exceptions import ResourceNotFoundError, HttpResponseError
from azure.servicebus import ServiceBusClient

if os.getenv("APPLICATIONINSIGHTS_CONNECTION_STRING"):
    from azure.monitor.opentelemetry import configure_azure_monitor
    configure_azure_monitor()
logging.basicConfig(level=logging.INFO)
log = logging.getLogger("inventory")

cred = DefaultAzureCredential()
inv = TableServiceClient(endpoint=os.environ["TABLES_ENDPOINT"], credential=cred).get_table_client("inventory")

def reserve(store, sku, qty):
    for _ in range(5):                                   # optimistic concurrency with ETags
        try:
            e = inv.get_entity(partition_key=store, row_key=sku)
        except ResourceNotFoundError:
            raise ValueError("UNKNOWN_SKU")
        if e["onHand"] < qty:
            raise ValueError("INSUFFICIENT_STOCK")
        e["onHand"] = e["onHand"] - qty
        try:
            inv.update_entity(e, mode=UpdateMode.REPLACE,
                              etag=e.metadata["etag"], match_condition=MatchConditions.IfNotModified)
            if e["onHand"] <= e["reorderPoint"]:
                log.warning("LOW_STOCK store=%s sku=%s onHand=%s", store, sku, e["onHand"])
            return
        except HttpResponseError as ex:
            if ex.status_code == 412:                    # someone else changed it: re-read and retry
                continue
            raise
    raise RuntimeError("CONTENTION")

with ServiceBusClient(os.environ["SB_FQDN"], cred) as sb, \
     sb.get_subscription_receiver("orders", "inventory") as rx:
    log.info("inventory-worker listening")
    while True:
        for msg in rx.receive_messages(max_message_count=10, max_wait_time=5):
            order = json.loads(str(msg))
            try:
                for line in order["lines"]:
                    reserve(order["storeId"], line["sku"], line["qty"])
                rx.complete_message(msg)
                log.info("RESERVED order=%s", order["orderId"])
            except ValueError as e:                      # business failure: send to DLQ, no retry
                rx.dead_letter_message(msg, reason=str(e))
                log.warning("DEAD_LETTERED order=%s reason=%s", order["orderId"], e)
            except Exception:                            # technical failure: retry up to 5 times
                rx.abandon_message(msg)
