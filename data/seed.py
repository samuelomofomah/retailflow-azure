import os
from azure.identity import DefaultAzureCredential
from azure.data.tables import TableServiceClient

svc = TableServiceClient(endpoint=os.environ["TABLES_ENDPOINT"], credential=DefaultAzureCredential())
for t in ["orders", "inventory", "products"]:
    svc.create_table_if_not_exists(t)

products = [
    {"sku": "SKU-1001", "category": "brakes",    "name": "Ceramic brake pads", "price": 79.99},
    {"sku": "SKU-1002", "category": "batteries", "name": "AGM battery 12V",    "price": 219.99},
    {"sku": "SKU-1003", "category": "fluids",    "name": "Synthetic oil 5L",   "price": 49.99},
]
prod, inv = svc.get_table_client("products"), svc.get_table_client("inventory")
for p in products:
    prod.upsert_entity({"PartitionKey": p["category"], "RowKey": p["sku"], "name": p["name"], "price": p["price"]})
    for store in ["store-101", "store-102", "store-103"]:
        inv.upsert_entity({"PartitionKey": store, "RowKey": p["sku"], "onHand": 25, "reorderPoint": 5})

print(f"seeded {len(products)} products and {len(list(inv.list_entities()))} inventory rows")
