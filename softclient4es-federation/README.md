# SoftClient4ES Federation Helm Chart

Deploys the ES-agnostic SoftClient4ES federation Arrow Flight SQL server.
(Sidecars — one per Elasticsearch cluster — are added in chart 0.2.x / Story 16.2.)

This release stands up a **single federation Pod** with **no downstream servers**
(`arrow.flight.federation.servers = {}`). It is the chart skeleton that later
revisions extend with sidecars (0.2.x), Secrets/TLS (0.3.x), topology examples,
CI smoke tests, and the full operator guide.

## Prerequisites

- Kubernetes 1.24+ (1.27+ recommended; native gRPC readiness probes land in chart 0.2.x).
- Helm 3.x.
- A container runtime able to pull from public DockerHub (`docker.io`).
- (Optional) a Kubernetes Secret holding the license JWT / API key — see `license.secretName`.

## Install

```sh
helm install fed ./softclient4es-federation
# or with overrides
helm install fed ./softclient4es-federation -f my-values.yaml
```

## Upgrade

```sh
helm upgrade fed ./softclient4es-federation -f my-values.yaml
```

## Rollback

```sh
helm history fed
helm rollback fed <REVISION>
```

## Uninstall

```sh
helm uninstall fed
```

## Notes

- **Health is gRPC, not HTTP.** This release runs the federation with NO downstream
  servers (`servers={}`). The health endpoint is the gRPC `grpc.health.v1.Health`
  service on port `32021` and reports `NOT_SERVING` until at least one sidecar is
  configured (chart 0.2.x). Therefore liveness/readiness here are **TCP-socket
  probes** (liveness → health port `32021`, readiness → Flight SQL port `32020`)
  that pass once the process is listening. Chart 0.2.x switches readiness to a
  native gRPC probe once sidecars make the `SERVING` aggregate meaningful (GA on
  Kubernetes 1.27+).
- **Deployable unlicensed (Community).** With `license.secretName` empty the
  federation boots in Community mode and reaches Ready (a no-downstream federation
  is within the Community single-cluster quota). Add `license.secretName` once you
  configure sidecars (0.2.x), where the cluster quota begins to apply.
- **Image availability.** The federation image
  `docker.io/softnetwork/softclient4es-federation:<tag>` is published to public
  DockerHub at R1 release (release/CI concern, OQ-1). Pin `image.tag` to the
  published release tag in your `values.yaml` (`--set image.tag=<tag>`); the chart
  default falls back to the Chart.yaml `appVersion`.
- **Read-only root filesystem.** `securityContext.readOnlyRootFilesystem: true` is
  paired with a writable `emptyDir` mounted at `/tmp`. This is **required for boot**:
  the DuckDB JDBC driver extracts its native library to `java.io.tmpdir` on startup
  even with `federation.duckdb.path: ":memory:"`. A file `duckdb.path` MUST point at
  a writable mount (under `/tmp` or a PersistentVolume).
- **Configuration reference.** Every value maps to an `arrow.flight.federation.*` /
  `FEDERATION_*` env var (see `values.yaml` comments).

## Configuration

| Key | Default | Description |
| --- | --- | --- |
| `replicaCount` | `1` | Number of federation Pods. |
| `image.repository` | `docker.io/softnetwork/softclient4es-federation` | Federation image repository. |
| `image.tag` | `""` (→ `.Chart.AppVersion`) | Image tag; empty falls back to `appVersion`. |
| `image.pullPolicy` | `IfNotPresent` | Image pull policy. |
| `federation.maxMemory` | `512m` | `FEDERATION_MAX_MEMORY` — DuckDB `memory_limit`. |
| `federation.queryTimeoutSeconds` | `30` | `FEDERATION_QUERY_TIMEOUT`. |
| `federation.health.port` | `32021` | `FEDERATION_HEALTH_PORT` (gRPC health). |
| `federation.health.probeTimeoutSeconds` | `5` | `FEDERATION_HEALTH_PROBE_TIMEOUT`; also K8s probe `timeoutSeconds`. |
| `federation.duckdb.path` | `:memory:` | `FEDERATION_DUCKDB_PATH`. |
| `federation.upgradeUrl` | `https://portal.softclient4es.com/pricing` | `FEDERATION_UPGRADE_URL`. |
| `telemetry.enabled` | `true` | `SOFTCLIENT4ES_TELEMETRY_ENABLED` daily-ping opt-out (`false` opts out). |
| `license.secretName` | `""` | Secret holding license/API key; empty = Community. |
| `service.type` | `ClusterIP` | Service type. |
| `service.port` | `32020` | `FEDERATION_PORT` (Flight SQL); the only port exposed by the Service. |
| `resources` | req `1Gi`/`500m`, lim `2Gi`/`1000m` | Container resource requests/limits. |
| `scratch.sizeLimit` | `2Gi` | Size limit of the writable `/tmp` `emptyDir`. |

## Regenerating the golden render

The committed render baseline at `tests/golden/default.yaml` lets a future PR detect
template drift. Regenerate (and review the diff) with:

```sh
helm template fed ./softclient4es-federation > ./softclient4es-federation/tests/golden/default.yaml
git diff --stat ./softclient4es-federation/tests/golden/default.yaml
```

Any diff must be intentional. CI (Story 16.5) enforces this golden plus `helm lint`
and `kubeconform -strict`.
