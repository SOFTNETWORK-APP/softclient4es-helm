# SoftClient4ES Federation Helm Chart

Deploys the ES-agnostic SoftClient4ES federation Arrow Flight SQL server plus,
optionally, one per-Elasticsearch-version Arrow Flight SQL **sidecar** per backing
Elasticsearch cluster (see the "Sidecars" section).

With the default `sidecars: []` the chart stands up a **single federation Pod** with
**no downstream servers** (`arrow.flight.federation.servers = {}`). Add entries to
`sidecars[]` to federate one or more (mixed-version) Elasticsearch clusters. Chart
0.3.x adds Kubernetes-Secret-backed credentials (incl. Secret-backed federation→sidecar
auth), TLS/Ingress termination, and secret-backend examples (see "Secrets, TLS & Ingress").
Later revisions add topology examples, CI smoke tests, and the full operator guide.

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
| `license.publicKeySecretName` | `""` | **Removed in appVersion 0.3.0** — the trust root is embedded in the image. Setting it aborts the render. Leave empty. |
| `license.publicKeyKey` | `""` | **Removed in appVersion 0.3.0** — see above. Leave empty. |
| `service.type` | `ClusterIP` | Service type. |
| `service.port` | `32020` | `FEDERATION_PORT` (Flight SQL); the only port exposed by the Service. |
| `resources` | req `1Gi`/`500m`, lim `2Gi`/`1000m` | Container resource requests/limits. |
| `scratch.sizeLimit` | `2Gi` | Size limit of the writable `/tmp` `emptyDir`. |
| `federation.probes.useGrpc` | `true` | When sidecars exist, use a native gRPC readiness probe (all-or-nothing — see below). `false` keeps TCP readiness. |
| `federation.tls.enabled` | `false` | Add a `tls:` block to the Ingress (TLS terminates at the Ingress; the pod is plaintext). See "Secrets, TLS & Ingress". |
| `federation.tls.secretName` | `""` | A `kubernetes.io/tls` Secret (`tls.crt`+`tls.key`), e.g. cert-manager-issued. |
| `federation.credentialsFromEnv` | `true` | Inject Secret-backed federation→sidecar creds via `CONFIG_FORCE_*` (`override_with_env_vars`). |
| `ingress.enabled` | `false` | Render an Ingress for the federation Flight SQL endpoint (gRPC — needs a gRPC-capable controller). |
| `ingress.className` | `""` | `spec.ingressClassName` (e.g. `nginx`). |
| `ingress.annotations` | `{}` | Free-form annotations (cert-manager / external-DNS / `backend-protocol: "GRPC"`). |
| `ingress.hosts` | (see `values.yaml`) | Host/path rules; an empty `host` renders no rule. |
| `ingress.tls` | `[]` | Explicit Ingress `tls:` entries; empty + `federation.tls.enabled` auto-fills from `federation.tls.secretName`. |
| `sidecars` | `[]` | Per-ES-version sidecars — see the "Sidecars" section below. |
| `sidecarDefaults` | (see `values.yaml`) | Shared resource/probe/security defaults applied to every sidecar. |
| `test.image` | `""` (→ `python:3.12-slim`) | Image for the `helm test` smoke Job; pin a pre-baked ADBC image for air-gapped clusters. |
| `test.adbcVersion` | `1.6.0` | ADBC driver version the smoke Job `pip install`s at runtime (when `test.image` is not pre-baked). |

## Sidecars — federating one or more Elasticsearch clusters

Each entry in `sidecars[]` deploys an Arrow Flight SQL gateway in front of ONE ES
cluster and registers it with the federation. Sidecars may target DIFFERENT ES
major versions (6/7/8/9) in the same deployment — the image is chosen automatically
from `elasticsearchVersion`. With `sidecars: []` (the default) the chart behaves
exactly like the 0.1.x federation-only skeleton (no Deployments/Services, no ConfigMap,
federation readiness stays TCP).

The backing-ES endpoint is given as a single `elasticsearch.url` (`scheme://host:port`),
which the chart decomposes into the `ELASTIC_SCHEME`/`ELASTIC_HOST`/`ELASTIC_PORT` env
the sidecar reads (there is no single ES-URL env var). A scheme-less url defaults to
`http`, a port-less url to `9200`; for a TLS or non-9200 cluster, supply the scheme/port
in the url or set explicit `elasticsearch.scheme`/`.host`/`.port`.

### Add a cluster
1. Append an entry to `sidecars[]` (name, elasticsearchVersion, elasticsearch.url,
   credentials Secret).
2. `helm upgrade fed ./softclient4es-federation -f my-values.yaml`

The federation ConfigMap is re-rendered and the federation Pod rolls automatically
(a `checksum/config` annotation forces the restart so the new cluster is picked up).

### Remove a cluster
1. Delete its entry from `sidecars[]`.
2. `helm upgrade …` — its Deployment + Service are removed; the federation ConfigMap
   is re-rendered and the federation Pod rolls (checksum/config annotation).

### Mixed ES versions
Fully supported — e.g. ES 8 in `us`, ES 9 in `eu`. Common during a version
migration: run mixed-version federation while migrating one cluster at a time.

### ⚠️ Licensing: a Pro/Enterprise license is REQUIRED once you have 2+ sidecars
The federation enforces a per-platform cluster QUOTA at startup. The quota — not a
feature flag — is the gate:

| Sidecars | Community (no license) | Pro | Enterprise |
|---|---|---|---|
| 1 | ✅ boots Ready (maxClusters=1) | ✅ | ✅ |
| 2–5 | ❌ federation CrashLoops (sys.exit) | ✅ (maxClusters=5) | ✅ |
| 6+ | ❌ | ❌ | ✅ (unlimited) |

So a **single-cluster** federation runs with NO license. The moment you add a
**second** sidecar you MUST set `license.secretName` to a **Pro** (≤5 clusters) or
**Enterprise** (unlimited) license, or the federation Pod CrashLoops by design.
(The Federation *feature* is present in all tiers; the limit is `maxClusters`.)

### Per-sidecar / federation auth (single source of truth)
A single `sidecars[].auth` block drives BOTH the sidecar's incoming `ARROW_AUTH_*`
auth AND the federation's outgoing `servers.<name>.credentials`. `method: none`
(default, intra-cluster trust) is the common case. For `basic`/`bearer`/`apikey`, the
SAME `auth.credentialsSecretName` Secret now feeds both sides (chart 0.3.x): the sidecar
reads `ARROW_AUTH_*` and the federation receives the value via `CONFIG_FORCE_*`
(`override_with_env_vars`) — see "Secrets, TLS & Ingress" below. Inline values are still
accepted for dev/test; the template fails fast with an actionable message if you set a
non-`none` method with neither a Secret nor inline creds.

### Cross-namespace deployments
Default is same-namespace (the ConfigMap uses `<svc>.<release-namespace>.svc...`).
Cross-namespace federation is possible by deploying sidecars in another namespace and
overriding the host; not the default — see the operator guide.

### ⚠️ Readiness behavior with multiple sidecars (`federation.probes.useGrpc`)
By default (`useGrpc: true`, K8s ≥ 1.27) the federation's gRPC readiness aggregate is
**all-or-nothing**: if **ANY ONE** downstream sidecar is unreachable, the federation Pod
goes **NotReady** and is removed from its Service — so **every** federation query fails,
including ones targeting the still-healthy sidecars. This is "fail-closed" routing. For
multi-sidecar production where partial availability is preferable, set
`federation.probes.useGrpc: false` to keep the (process-listening) TCP readiness — the
federation stays Ready and degrades per-query instead of dropping entirely. On K8s < 1.27
you MUST use `useGrpc: false` (native gRPC probes are GA only from 1.27; `grpc_health_probe`
exec is the compat path — see the operator guide).

### `helm test` smoke
With sidecars configured, `helm test fed` runs a Job that connects to the federation
Flight SQL endpoint and asserts `GetCatalogs` returns one catalog per sidecar
(`len(sidecars)`). The 2-sidecar smoke requires a Pro/Enterprise license (the quota
gate above) and reachable backing ES for each sidecar. The Job **retries the connect +
`GetCatalogs` for up to ~60 s** — the federation is NotReady until it has discovered every
downstream (gRPC readiness is all-or-nothing), so a fresh install needs a few seconds.

The test Pod defaults to `python:3.12-slim` and `pip install`s the ADBC driver at runtime
(needs PyPI reachability). For air-gapped or rate-limited clusters, pin a pre-baked ADBC image
with `--set test.image=<image>` (and `--set test.adbcVersion=<v>` to control the driver version
when the runtime install IS used). This is the same Job CI runs.

> **Offline license verification (appVersion 0.3.0 and later).** Nothing to configure. The
> licence trust root is embedded in the image, so a licence issued by the SoftClient4ES licence
> server verifies with no network access and no extra values — air-gapped clusters included.
> `SOFTCLIENT4ES_LICENSE_PUBLIC_KEY` is no longer consulted, and `license.publicKeySecretName`
> now **aborts the render** rather than becoming a silent no-op. Remove it from your values.

## Secrets, TLS & Ingress

The chart **references** Kubernetes Secrets by name and never creates them. See
[`docs/secret-backends.md`](docs/secret-backends.md) for how to create them (raw /
SealedSecrets / ESO / Vault), and `examples/sealed-secrets/` + `examples/external-secrets/`
for ready-to-adapt manifests.

### Secret key-name contract
Each referenced Secret must carry these data keys (override per-sidecar via `secretKeys`):

| values.yaml field | Secret data keys |
|---|---|
| `sidecars[].elasticsearch.credentialsSecretName` | `es-auth-method`, `es-username`, `es-password`, `es-api-key`, `es-bearer-token` |
| `sidecars[].auth.credentialsSecretName` | `arrow-username`, `arrow-password`, `arrow-bearer-token`, `arrow-api-key` |
| `license.secretName` | `license-key`, `api-key` |
| `federation.tls.secretName` | `tls.crt`, `tls.key` (`kubernetes.io/tls`) |

Override the data-key names per sidecar with `elasticsearch.secretKeys` / `auth.secretKeys`,
or mount the whole Secret as env with `useEnvFrom: true` (the Secret's keys must then BE the
env-var names — no remapping).

> **A Secret with the WRONG keys is silent at install time.** The chart's `secretKeyRef`s are
> `optional: true`, so a key-name mismatch (or a Secret not created/synced yet) does NOT fail
> `helm install` — the env is simply absent, and the federation then CrashLoops at boot with a
> `FlightCredentials`/`validate()` credentials error (the sidecar may start but fail its ES/auth
> connection). If a pod CrashLoops right after a Secret-backed install, check: the Secret EXISTS
> (`kubectl get secret <name>`), its data keys MATCH this table
> (`kubectl get secret <name> -o jsonpath='{.data}'`), and — for ESO/SealedSecrets — it has
> MATERIALIZED (`kubectl get externalsecret` / `kubectl get sealedsecret`, sealed for THIS
> namespace). An ESO sync-lag CrashLoop **self-heals** on the next restart once the Secret
> appears — do not uninstall prematurely.

### Federation → sidecar credentials (single Secret, both sides)
ONE `sidecars[].auth.credentialsSecretName` feeds BOTH the sidecar's incoming `ARROW_AUTH_*`
AND the federation's outgoing auth to that sidecar. Because a ConfigMap cannot read a Secret,
the federation receives the credential via Typesafe Config `override_with_env_vars`: the chart
sets `-Dconfig.override_with_env_vars=true` and injects
`CONFIG_FORCE_arrow_flight_federation_servers_<name>_credentials_<key>` env from the Secret
(toggle: `federation.credentialsFromEnv`, default `true`). The ConfigMap renders only the
`method` (not secret); the value arrives from the Secret. **Sidecar names must be strict
RFC1123 labels** — the name is mangled into the `CONFIG_FORCE_*` path, and a `_`/`.`/uppercase
would silently mis-target it (the template fails fast on a non-RFC1123 name). `auth.useEnvFrom`
(whole-Secret mode) is **incompatible** with a Secret-backed federation→sidecar credential —
the federation reads the Secret per-key (`arrow-bearer-token`, …), which a whole-Secret-shaped
Secret does not carry — so the chart fails fast on that combination; use the per-key default
(`useEnvFrom: false`) for any non-`none` Secret-backed auth method.

> **Rotation needs a restart.** Env-from-Secret is read at Pod start, so rotating the Secret
> value needs `kubectl rollout restart deploy/<fullname>` (or a reloader of your choice). When
> ONE Secret feeds BOTH the sidecar (`ARROW_AUTH_*`) and the federation (`CONFIG_FORCE_*`),
> restart BOTH Deployments or the two sides drift (the federation presents the old credential
> to a sidecar that now expects the new one).

### `auth.method=none` + a Secret (benign)
Setting `auth.credentialsSecretName` while `auth.method: none` is harmless — the sidecar's
server-side auth is off, the injected `ARROW_AUTH_*` env are ignored, and the federation emits
no `CONFIG_FORCE_*` for that sidecar. The chart does NOT fail this (you may pre-stage a Secret
before flipping `method`); just note the Secret has no effect until `method` is non-`none`.

### TLS (at the Ingress, not the Pod)
The federation Flight SQL server listens **plaintext gRPC only** — it does NOT terminate TLS.
Terminate TLS at an Ingress/gateway: set `federation.tls.enabled` + `federation.tls.secretName`
(a cert-manager `kubernetes.io/tls` Secret) and `ingress.enabled`. Flight SQL is gRPC, so the
Ingress controller MUST proxy gRPC backends with `backend-protocol: "GRPC"` (**NOT** `GRPCS` —
the pod is plaintext; the Ingress terminates TLS and forwards cleartext h2c), or use a
Gateway-API gateway. nginx-ingress speaks HTTP/2 to clients only over a TLS listener, so
Flight-SQL-over-Ingress in practice means TLS-at-the-edge; for plaintext in-cluster access, hit
the ClusterIP/LoadBalancer Service (`32020`) directly rather than a plaintext Ingress.
`sidecars[].tls: true` is a SEPARATE knob — it makes the federation connect to THAT sidecar over
TLS (the outgoing hop), unrelated to the federation's own inbound edge TLS.

### Example currency
The `examples/external-secrets/` use `external-secrets.io/v1` (the stable API; `v1beta1` was
removed at ESO v0.17.0). The `examples/sealed-secrets/` reference the post-move repo
`bitnami.github.io` and are NON-FUNCTIONAL placeholders that MUST be re-sealed per cluster (and
per namespace — SealedSecrets are namespace-scoped by default).

## Regenerating the golden render

The committed render baselines under `tests/golden/` let a future PR detect template
drift: `default.yaml` (0 sidecars), `two-sidecars.yaml` (federation + 2 mixed ES8/ES9
sidecars), `secret-auth.yaml` (1 sidecar, Secret-backed ES + sidecar bearer auth +
federation `CONFIG_FORCE_*`), and `ingress-tls.yaml` (federation behind a cert-manager
TLS Ingress). The `example-*.yaml` baselines render the three topology examples under
`examples/` (Story 16.4). Regenerate (and review the diff) with:

```sh
helm template fed ./softclient4es-federation > ./softclient4es-federation/tests/golden/default.yaml
helm template fed ./softclient4es-federation -f ./softclient4es-federation/tests/values/two-sidecars.yaml \
  > ./softclient4es-federation/tests/golden/two-sidecars.yaml
helm template fed ./softclient4es-federation -f ./softclient4es-federation/tests/values/secret-auth.yaml \
  > ./softclient4es-federation/tests/golden/secret-auth.yaml
helm template fed ./softclient4es-federation -f ./softclient4es-federation/tests/values/ingress-tls.yaml \
  > ./softclient4es-federation/tests/golden/ingress-tls.yaml
# Topology examples (Story 16.4):
helm template fed ./softclient4es-federation -f ./softclient4es-federation/examples/single-cluster/values.yaml \
  > ./softclient4es-federation/tests/golden/example-single-cluster.yaml
helm template fed ./softclient4es-federation -f ./softclient4es-federation/examples/three-region/values.yaml \
  > ./softclient4es-federation/tests/golden/example-three-region.yaml
helm template fed ./softclient4es-federation -f ./softclient4es-federation/examples/heterogeneous-ready/values.yaml \
  > ./softclient4es-federation/tests/golden/example-heterogeneous-ready.yaml
git diff --stat ./softclient4es-federation/tests/golden/
```

Any diff must be intentional. CI (Story 16.5) enforces these goldens plus `helm lint`
and `kubeconform -strict` (including the 2-sidecar, Secret-backed, and TLS/Ingress renders).
The chart `templates/` must emit ZERO `kind: Secret` — assert with
`helm template fed ./softclient4es-federation -f … | grep -c '^kind: Secret'` (expected `0`).

> **`example-three-region.yaml` and `example-heterogeneous-ready.yaml` are BYTE-IDENTICAL
> by design** — `diff` between them is EMPTY (Story 16.4 Decision A2). The two `values.yaml`
> overlays carry the SAME active values (same license Secret, telemetry, `useGrpc`, and the
> same three `sidecars[]`); they differ ONLY in comments and the commented-out R2b
> `duckdb-attach` preview, and Helm strips all comments before rendering. The ONLY signal
> distinguishing the two examples is the SOURCE: `examples/heterogeneous-ready/values.yaml`
> contains the `type = "duckdb-attach"` R2b marker and `examples/three-region/values.yaml`
> does not (Decision A2b) — CI (16.5) greps for this. A regression that overwrote one
> overlay with the other would pass the golden + `helm test` gates but FAIL the grep.

## Topology examples

Copy-pasteable `values.yaml` overlays for three operator scenarios live under `examples/`
(Story 16.4). Each has its own `README.md` with a "when to use", an ASCII topology diagram,
the install command, and the `SHOW CATALOGS` smoke expectation:

| Example | Topology | License | `SHOW CATALOGS` |
|---|---|---|---|
| `examples/single-cluster/` | federation + 1 ES8 sidecar | **none** (Community, `maxClusters=1`) | 1 |
| `examples/three-region/` | federation + us-east-1 (ES8) / eu-west-1 (ES8) / ap-south-1 (ES9) | **Pro / Enterprise** | 3 |
| `examples/heterogeneous-ready/` | three-region today + a commented R2b `duckdb-attach` preview (PG/MySQL/Snowflake) | **Pro / Enterprise** | 3 (R2b inactive) |

Install any of them with `helm install softclient4es-federation softclient4es-federation -f examples/<x>/values.yaml`
(create the referenced Secrets first — see each example's README).

## CI / CD coverage (Story 16.5)

Every PR touching `softclient4es-federation/**` runs
[`.github/workflows/federation-helm.yml`](../.github/workflows/federation-helm.yml): static
checks (lint + template + `kubeconform -strict` + golden-file diff), an image-availability
prerequisite (pulls the public DockerHub federation + sidecar images), and per-topology /
per-ES-version / secret-backend / upgrade / uninstall installs on ephemeral `kind` clusters.
The smoke test is the chart's own `helm test` Job (ADBC Flight SQL `GetCatalogs`, asserting one
catalog per sidecar) — customers run the exact same `helm test fed` post-install that CI runs.

This chart repo is **chart-only** (no sbt build): CI never builds images. The live-install jobs
`docker pull` the public DockerHub images and `kind load` them. Until those images are published
(OQ-1), the live-install jobs **probe image availability and skip with a CI annotation** rather
than fail — the static-validation gates run unconditionally on every PR with zero external deps.

### Tested vs best-effort matrix

| Scenario | Gate | Tier | License | Notes |
|---|---|---|---|---|
| `helm lint` (chart + each example) | static | **tested** (blocker) | none | unconditional |
| `helm template` + `kubeconform -strict` | static | **tested** (blocker) | none | per example |
| Golden-file diff (template drift) | static | **tested** (blocker) | none | per example + the 16.1/16.2/16.3 goldens |
| Zero `kind: Secret` rendered | static | **tested** (blocker) | none | 16.3 contract |
| `heterogeneous-ready` discriminator | static | **tested** (blocker) | none | greps the `type = "duckdb-attach"` marker (the only signal vs `three-region` — the goldens are byte-identical) |
| Install single-cluster (1×ES8) | kind | **tested** | none (Community) | `GetCatalogs` == 1 |
| Install three-region (2×ES8 + 1×ES9) | kind | **best-effort\*** | **Pro** | mixed-version; `== 3` |
| Install heterogeneous-ready (3×ES) | kind | **best-effort\*** | **Pro** | R2b placeholders inactive; `== 3` |
| Per-ES-version sidecar (6/7/8/9) | kind | **tested** | none | 1 sidecar each; `== 1` |
| Secret backend: raw K8s Secret | kind | **tested** | none | 1 sidecar Secret-backed |
| Secret backend: SealedSecrets | kind | **tested** | none | controller installed + re-sealed in-cluster |
| Secret backend: External Secrets Operator (ESO) | — | **best-effort / documented** | — | needs an external store; examples shipped (16.3), not CI-run |
| Secret backend: Vault Agent Injector | — | **best-effort / documented** | — | needs Vault; documented (16.3) |
| Upgrade single → three-region | kind | **best-effort\*** | **Pro** | topology change asserted (+2 sidecar Deployments) |
| Uninstall clean | kind | **tested** | none | `kubectl get all` empty |

\* The multi-cluster (Pro) tiers run only when ALL of: (1) the federation image bundles the
JWT-verifying SPI (a **Pro-capable** image — an OSS-only image ships only the Community SPI and
cannot verify ANY Pro JWT), and (2) the `SC4ES_PRO_TEST_JWT` repo secret, holding a JWT **issued
by the SoftClient4ES licence server** (since appVersion 0.3.0 a self-signed test JWT can no longer
be made to verify by supplying its public key) are present. Otherwise they are
**skipped with a CI annotation** (not a failure). A **single-cluster** federation is license-FREE
(Community `maxClusters=1`) and is always tested; the static three-region/heterogeneous golden
proves the mixed-version RENDER on every PR even when the live multi-cluster install is skipped.

### Image tags in CI

The live-install jobs resolve the chart's DEFAULT image refs (federation `image.tag:""` →
`appVersion`; sidecar tag → `appVersion`), `docker pull` those public DockerHub tags, and
`kind load` them — no per-image `--set image.tag` override, so the federation + sidecar tags
stay consistent with the committed goldens (which are `appVersion` renders). Until the images
are published (OQ-1), an availability probe (`docker manifest inspect`) gates each live-install
job: if a required image is absent the job is **skipped with a `::warning::` annotation**, never
failed. The golden gate renders with NO `--set image.tag`.

### CI failure modes (troubleshooting)

| CI job fails with… | Likely cause | Fix |
|---|---|---|
| golden-file diff non-empty | a template change was not regenerated | run the regen commands above; commit the new golden if the change is intentional |
| `kubeconform` invalid resource | a manifest field renamed/typo (e.g. `replicaCount` vs `replicas`) | fix the template; `replicas` is the Deployment field |
| `heterogeneous-ready` discriminator fails | `three-region` and `heterogeneous-ready` overlays drifted (one copied over the other) | restore the commented R2b `duckdb-attach` preview in `heterogeneous-ready` (the goldens are byte-identical — this grep is the only signal) |
| federation pod CrashLoopBackOff (3 sidecars, license supplied but Community at runtime) | the image lacks the JWT SPI — it cannot verify the Pro JWT → falls back to Community → `maxClusters=1` exceeded | use a Pro-CAPABLE federation image (JWT SPI on classpath, 16.1 OQ-5); injecting a JWT into an OSS-only image does nothing |
| federation pod CrashLoopBackOff (`InvalidLicense: Unknown key ID: …`) | the JWT was not signed by a key this image trusts — as of appVersion 0.3.0 the trust root is embedded, so a self-signed or test-signed JWT can no longer be made to verify | use a licence issued by the SoftClient4ES licence server. Supplying a public key is no longer possible and `license.publicKeySecretName` now aborts the render |
| federation pod CrashLoopBackOff (3 sidecars, no license at all) | Community `maxClusters=1` exceeded | supply a Pro/Enterprise license (`license.secretName`) — by design |
| federation pod CrashLoopBackOff (`validate()` / `FlightCredentials`) | Secret-backed cred didn't arrive (wrong key / ESO sync lag) | check the Secret exists + keys match the contract table above; self-heals on next restart |
| federation NotReady, smoke connect-refused | a sidecar's backing ES is down/unreachable (all-or-nothing gRPC readiness) | ensure every sidecar's ES is reachable; or set `federation.probes.useGrpc=false` for partial availability |
| `helm test` count mismatch | a sidecar failed discovery (ES down, or wrong `elasticsearch.url`) | check sidecar + ES logs; verify each sidecar's `elasticsearch.url` resolves in-cluster |
| image pull error (federation OR sidecar) | the public DockerHub tag is not published yet (OQ-1) | the availability probe should skip the live-install job until the image is published; once published, the job `docker pull`s + `kind load`s the public tag |
| live-install job skipped with a `::warning::` | the required public DockerHub image is not yet published (OQ-1) | expected until release; the static-validation gates still run unconditionally |
| ES pod crash (`max virtual memory areas …`) | `vm.max_map_count` too low | `sudo sysctl -w vm.max_map_count=262144` on the runner before ES starts (the workflow does this) |

### Duration & sharding

Static checks < 2 min; image pull ~1–2 min; each install job ~6–9 min (when the public images
exist — otherwise the live jobs skip in seconds). With the matrix in parallel, wall-clock ≈
image-pull + slowest install ≈ ~12 min (< 30 min budget). If runner contention serializes the
matrix past 30 min, move the per-ES-version + secret-backend jobs to a `schedule:` nightly
trigger (uncomment the `schedule:` block in the workflow) and keep PRs to static-checks +
single-cluster + three-region + uninstall.
