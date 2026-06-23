# Single-cluster federation (FREE tier)

Federation Flight SQL server in front of **one** Elasticsearch cluster, via one
Arrow Flight SQL sidecar. Runs on the **Community license — no license key needed**
(the cluster quota is `maxClusters=1`, and one sidecar fits).

## When to use this

- You have ONE Elasticsearch cluster and want a **Flight SQL endpoint** for it
  (BI tools, ADBC, JDBC-over-Flight) with **cross-index JOIN routing** and licensing,
  exposed externally — without standing up the federation + sidecar HOCON + probes by hand.
- You want to **start free** and grow into multi-region later: add a second `sidecars[]`
  entry + a Pro license and you have the three-region topology (see `../three-region/`).

## Topology

```
                       ┌─────────────────────────────┐
   Flight SQL client   │  Federation (Flight SQL)    │
   (BI / ADBC / JDBC) ─┼─► :32020  softclient4es-     │
                       │     federation              │
                       │  health gRPC :32021         │
                       └──────────────┬──────────────┘
                                      │ in-cluster gRPC (plaintext)
                                      ▼
                       ┌─────────────────────────────┐
                       │  Sidecar: primary (ES 8)    │
                       │  Arrow Flight SQL :32010    │
                       └──────────────┬──────────────┘
                                      │ ELASTIC_SCHEME/HOST/PORT
                                      ▼
                       ┌─────────────────────────────┐
                       │  Elasticsearch  (1 cluster) │
                       │  es.example.com:9200        │
                       └─────────────────────────────┘
```

## Install

```bash
# Create the ES credentials Secret (skip for a noauth ES):
kubectl create secret generic sc4es-es-credentials \
  --from-literal=es-auth-method=basic \
  --from-literal=es-username=elastic \
  --from-literal=es-password='<your-password>'

helm install softclient4es-federation softclient4es-federation \
  -f examples/single-cluster/values.yaml \
  --set sidecars[0].elasticsearch.url=https://YOUR-ES:9200
```

> **`elasticsearch.url` must be `scheme://host:port`.** The chart decomposes it into
> `ELASTIC_SCHEME`/`ELASTIC_HOST`/`ELASTIC_PORT` (there is no single ES-URL env). A
> scheme-less value defaults to `http`; a port-less value defaults to `9200`. For a
> TLS or non-9200 cluster, always include `https://` and the explicit port, or set
> `elasticsearch.scheme`/`.host`/`.port` directly (explicit fields win over `url`).

## Verify

```bash
helm test softclient4es-federation     # SHOW CATALOGS returns 1 (the `primary` cluster)
```

`SHOW CATALOGS` (or ADBC `get_objects(depth="catalogs")`) returns **1** catalog.

## Licensing

**No license required.** A single-cluster federation runs on Community
(`maxClusters=1`). The moment you add a **second** sidecar you need a Pro/Enterprise
license — see `../three-region/README.md`.
