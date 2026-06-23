# Heterogeneous-ready federation (R1 today → R2b tomorrow) — Pro / Enterprise

Runs the **three-region ES topology TODAY on R1** (3 Elasticsearch sidecars), and is
laid out so the **R2b heterogeneous sources** (PostgreSQL, MySQL, Snowflake, …) slot
into the **same federation `servers` map** when R2b ships — **no restructuring** of
this deployment.

## What works today (R1)

Exactly the three-region topology: a Flight SQL endpoint federating 3 ES clusters
(us-east-1 ES 8, eu-west-1 ES 8, ap-south-1 ES 9), with cross-cluster JOIN. Needs a
**Pro/Enterprise license** (3 clusters > Community's `maxClusters=1`) — see the
quota table in `../three-region/README.md`.

## What slots in tomorrow (R2b)

The federation `servers` map already supports `type = "duckdb-attach"` entries
(PostgreSQL / MySQL / Snowflake / … via DuckDB ATTACH). When R2b ships, those join
the SAME map your ES sidecars register into — a relational source becomes a federated
catalog you can `JOIN` against your ES indices, with no change to the federation
deployment topology. The `values.yaml` carries a commented preview of the exact HOCON.

> ⚠️⚠️ **The R2b preview in `values.yaml` is INERT on R1 — uncommenting it does NOTHING.**
> R1 has **no `values.yaml` key** that parses `duckdb-attach` (or a raw `servers { }`
> HOCON map). The federation `servers` map is rendered into a ConfigMap **entirely from
> the `sidecars[]` array** (Flight SQL sidecars only). If you uncomment the preview block
> and `helm install`, Helm discards it as comments, the chart ignores it, no relational
> catalog appears, and `SHOW CATALOGS` still returns **3** (the ES sidecars). The block is
> a documentation illustration of the FUTURE R2b shape — not an activation switch. R2b
> (Epic 25/26) is what makes these sources live.

> ⚠️ **Quota note:** each active `duckdb-attach` server ALSO counts toward `maxClusters`
> (`clusterCount = servers.size`). 3 ES + 3 attach = 6 clusters would exceed Pro's
> `maxClusters=5` → you'd need Enterprise. (A smaller mix still fits Pro: 3 ES + 2 attach
> = 5 clusters is exactly Pro's cap; only the 6th server tips you into Enterprise.) Plan
> your tier before activating R2b sources.

## Topology

```
                        ┌──────────────────────────────────┐
   Flight SQL client ───┼─►  Federation (Flight SQL :32020) │
                        └───┬────────┬────────┬─────────────┘
              R1-ACTIVE     │        │        │
              ┌─────────────▼┐ ┌─────▼──────┐ ┌▼────────────┐
              │ us-east-1 ES8│ │ eu-west-1  │ │ ap-south-1  │
              │ sidecar      │ │ ES8 sidecar│ │ ES9 sidecar │
              └──────────────┘ └────────────┘ └─────────────┘

              R2b-PREVIEW (commented; slot into the SAME servers map)
              ┌╌╌╌╌╌╌╌╌╌╌╌╌╌┐ ┌╌╌╌╌╌╌╌╌╌╌╌╌┐ ┌╌╌╌╌╌╌╌╌╌╌╌╌╌┐
              ┊ analytics_pg ┊ ┊ orders_mysql┊ ┊ snowflake_wh ┊
              ┊ (PostgreSQL) ┊ ┊  (MySQL)    ┊ ┊ (Snowflake)  ┊
              └╌╌╌╌╌╌╌╌╌╌╌╌╌┘ └╌╌╌╌╌╌╌╌╌╌╌╌┘ └╌╌╌╌╌╌╌╌╌╌╌╌╌┘
                       (duckdb-attach — Epic 25/26)
```

## Install (R1)

Same as three-region (Pro license + per-region Secrets), then:

```bash
helm install softclient4es-federation softclient4es-federation \
  -f examples/heterogeneous-ready/values.yaml
```

## Verify

```bash
helm test softclient4es-federation     # SHOW CATALOGS returns 3 (the active ES clusters)
```

The R2b `duckdb-attach` placeholders are **commented out** — they do not register
and do not count toward `SHOW CATALOGS` (which returns **3**) until R2b activates them.
