# Three-region federation (mixed ES versions) — Pro / Enterprise

Federation + 3 region sidecars: **us-east-1 (ES 8)**, **eu-west-1 (ES 8)**,
**ap-south-1 (ES 9)**. One Flight SQL endpoint federating three Elasticsearch
clusters across regions and ES major versions.

## ⚠️ Licensing — a Pro (or Enterprise) license is REQUIRED

3 sidecars = 3 clusters. The federation enforces a per-platform cluster **quota**
at startup (it is the `maxClusters` quota, **not** a feature flag):

| Clusters (sidecars) | Community (no license) | Pro | Enterprise |
|---|---|---|---|
| 1 | ✅ Ready (maxClusters=1) | ✅ | ✅ |
| 2–5 | ❌ federation CrashLoops (sys.exit) | ✅ (maxClusters=5) | ✅ |
| 6+ | ❌ | ❌ | ✅ (unlimited) |

So this example **will not boot** without a Pro/Enterprise license. Create the
license Secret BEFORE `helm install`:

```bash
kubectl create secret generic sc4es-pro-license --from-literal=license-key="$SC4ES_PRO_JWT"
```

(The federation surfaces the upgrade URL it emits at startup if you forget.)

> ⚠️ **A Pro JWT alone is not enough — the federation IMAGE must be able to verify it.**
> Offline JWT verification is performed by a closed-source license manager that is
> bundled ONLY in the Pro/Enterprise-capable federation image. The Community/OSS image
> ships only the Community license manager, so it ignores any injected JWT, resolves to
> Community (`maxClusters=1`), and **still CrashLoops** on this 3-cluster example. The
> image must ALSO be able to resolve the license SIGNING public key offline (env
> `SOFTCLIENT4ES_LICENSE_PUBLIC_KEY`, or the issuer's JWKS endpoint must be reachable).
> Use a Pro/Enterprise-entitled federation image + provision the public key; consult the
> licensing/operator guide for the exact image + key provisioning. This precondition is
> tracked for the CI/install path (Story 16.5 FACT F / Story 16.1 OQ-5). A bare
> `--set image.tag` of the OSS snapshot image WILL CrashLoop even with a valid JWT Secret.

## When to use this — three wedges

- **GDPR data residency.** `eu-west-1` keeps EU data in the EU; the federation can
  still run a cross-cluster JOIN that *references* it without copying rows across
  borders (the JOIN executes in the federation; each region's data stays home).
- **SRE incident triage** (R1 marketing wedge). During an incident, one Flight SQL
  endpoint lets an SRE `JOIN` logs/metrics/traces indices that live in **different
  regional clusters** — no per-cluster console hopping, no ETL. A single query
  correlates `us-east-1.errors` with `ap-south-1.upstream_latency`.
- **Mixed-version migration window.** Run ES 8 in `us-east-1` + `eu-west-1` while
  `ap-south-1` is migrated to ES 9 — the federation routes across versions
  transparently (the per-region sidecar image is chosen from `elasticsearchVersion`).
  No "big bang" cutover; migrate one region at a time and keep federating throughout.

## Topology

```
                        ┌──────────────────────────────────┐
   Flight SQL client    │  Federation (Flight SQL :32020)  │
   (BI / ADBC / JDBC) ──┼─►  softclient4es-federation       │
                        │   health gRPC :32021 (aggregate)  │
                        └───┬────────────┬────────────┬─────┘
                            │            │            │  in-cluster gRPC
              ┌─────────────▼──┐  ┌──────▼───────┐  ┌─▼──────────────┐
              │ us-east-1      │  │ eu-west-1    │  │ ap-south-1     │
              │ sidecar (ES 8) │  │ sidecar(ES 8)│  │ sidecar (ES 9) │
              │ :32010 default │  │ :32010       │  │ :32010         │
              └────────┬───────┘  └──────┬───────┘  └───────┬────────┘
                       ▼                 ▼                  ▼
              ┌────────────────┐ ┌────────────────┐ ┌────────────────┐
              │ ES 8  us-east-1│ │ ES 8  eu-west-1│ │ ES 9 ap-south-1│
              │ (US data)      │ │ (EU data/GDPR) │ │ (migrating→ES9)│
              └────────────────┘ └────────────────┘ └────────────────┘
```

## Install

```bash
# 1. Pro license Secret (REQUIRED):
kubectl create secret generic sc4es-pro-license --from-literal=license-key="$SC4ES_PRO_JWT"

# 2. Per-region ES + sidecar-auth Secrets (chart does NOT create these):
for r in us-east-1 eu-west-1 ap-south-1; do
  kubectl create secret generic sc4es-es-$r \
    --from-literal=es-auth-method=basic --from-literal=es-username=elastic --from-literal=es-password='<pwd>'
  kubectl create secret generic sc4es-arrow-$r --from-literal=arrow-bearer-token='<token>'
done

# 3. Install:
helm install softclient4es-federation softclient4es-federation \
  -f examples/three-region/values.yaml
```

## Verify

```bash
helm test softclient4es-federation     # SHOW CATALOGS returns 3
```

## Readiness & the all-or-nothing aggregate (important for multi-region)

With `federation.probes.useGrpc: true` (default, K8s ≥ 1.27) the federation's gRPC
readiness aggregate is **all-or-nothing**: if **ANY ONE** region's sidecar is
unreachable, the federation Pod goes **NotReady** and is pulled from its Service —
so **every** query fails, including ones targeting the healthy regions. This is
"fail-closed" routing. For multi-region production where partial availability is
preferable (keep serving the healthy regions, fail only the queries that touch the
down region), set `federation.probes.useGrpc: false` (TCP readiness — the federation
stays Ready and degrades per-query). On K8s < 1.27 you MUST use `useGrpc: false`.
