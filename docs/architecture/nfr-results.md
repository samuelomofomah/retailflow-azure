# NFR test results (19-20 Nov 2026)

| Quality | Target | Test | Measured result |
|---|---|---|---|
| Availability | Orders accepted while inventory is down | B: worker revision deactivated, orders placed | 8/8 accepted (HTTP 201) during the outage; backlog drained after reactivation; stock 25 to 17, no orders lost |
| Data integrity | No lost stock updates under contention | C: 20 parallel 1-unit orders for one SKU | Stock 25 to exactly 5 |
| Resiliency | Bad orders don't block good ones | A: qty 999 and unknown SKU | Both dead-lettered with reasons (INSUFFICIENT_STOCK, UNKNOWN_SKU); dead-letter alert emailed |
| Idempotency | Retries never duplicate orders | Same Idempotency-Key sent twice | 201 then 200 with the same orderId and createdAt |
| Security | Gateway is the only entry point | Direct call to the Container App | 401 |
| Protection | One client can't overload the backend | D: 40 reads in a burst | 29 x 200, then 11 x 429 at the gateway |
| Performance | p95 under 800 ms for POST /orders | KQL on AppRequests, before and after fix | **v1: p50 [__] ms, p95 [__] ms (FAILED).** Root cause: a new Service Bus connection (AMQP link + TLS + token) opened per request. **v2: one sender reused for the app's lifetime: p50 [__] ms, p95 [__] ms** |
| Observability | Business events visible in telemetry | KQL on AppTraces | RESERVED, DEAD_LETTERED and LOW_STOCK all reported. Found and fixed a logging-order bug that was dropping INFO events |
| Elasticity | Worker costs nothing when idle | KEDA scale rule 0 to 5 on queue depth | Worker at 0 replicas between tests; scaled up on backlog |

## Findings and fixes
1. **Per-request Service Bus connections** made POST /orders p95 about 3.8 s. Fixed by reusing one sender, guarded by a lock because FastAPI runs sync handlers on a thread pool. At higher scale: async handlers or a sender pool.
2. **Logging configured after Azure Monitor** silently left the root logger at WARNING, so INFO events (RESERVED) were never exported. Fixed by configuring logging first and holding Azure SDK logs at WARNING.
3. **Health probes dominate request telemetry** (about 6,800 GET /healthz calls a day). Queries filter them out; production would sample or drop them at the exporter.
