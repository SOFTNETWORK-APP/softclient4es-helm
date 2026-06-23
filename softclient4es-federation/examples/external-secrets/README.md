# External Secrets Operator (ESO) examples (Story 16.3)

These manifests sync secrets from a managed store (AWS Secrets Manager / GCP Secret Manager /
HashiCorp Vault) into the native Kubernetes Secrets the chart references, via
[External Secrets Operator](https://external-secrets.io). The cloud store is the source of
truth; ESO refreshes on an interval. The chart never creates a Secret — ESO does.

| File | Backend | Materializes Secret | Chart reference |
|---|---|---|---|
| `aws-secrets-manager.externalsecret.yaml` | AWS Secrets Manager | `es-prod-us` | `sidecars[].elasticsearch.credentialsSecretName` |
| `gcp-secret-manager.externalsecret.yaml` | GCP Secret Manager | `prod-us-arrow-auth` | `sidecars[].auth.credentialsSecretName` (feeds BOTH sides) |
| `vault.externalsecret.yaml` | HashiCorp Vault (KV v2) | `es-prod-us` | `sidecars[].elasticsearch.credentialsSecretName` |

## API version

All examples use **`external-secrets.io/v1`** — the STABLE ESO API. `v1beta1` was deprecated
then **removed at ESO v0.17.0** (the webhook auto-converts `v1beta1` → `v1` from v0.16.x), so a
`v1beta1` example fails `kubectl apply` on a current ESO. On ESO **< 0.16** substitute
`v1beta1`.

## Map remote keys to the chart-expected keys

Each `ExternalSecret.spec.data[].secretKey` MUST be a chart-expected data key (see the chart
README "Secret key-name contract"), e.g. `es-username`, `es-password`, `arrow-bearer-token`.
Point `remoteRef` at wherever the value lives in your managed store.

## CI / validation note

ESO CRDs are **not** in the default kubeconform schema set, so these examples are
schema-validated only when an ESO `-schema-location` is supplied (otherwise skipped, not
failed). A **live** ESO sync needs a real cloud store / Vault, so the ESO + Vault paths are the
**documented best-effort** tier (the raw-Secret and SealedSecrets paths are the CI-tested tier —
see Story 16.5).

## Vault Agent Injector (alternative)

The `vault.externalsecret.yaml` here uses ESO's Vault provider. The Vault **Agent Injector**
(sidecar injection via pod annotations) is a different integration — it injects a file, not a
K8s Secret — covered in `../../docs/secret-backends.md`.
