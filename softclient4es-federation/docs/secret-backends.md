# Choosing a secret backend

The SoftClient4ES federation chart **references** Kubernetes Secrets by name but never
creates them — so you bring your own secret-management workflow. The chart expects each
Secret to carry specific data keys (see the README "Secret key-name contract" table); the
four common ways to populate them are below. The chart prescribes none — pick what fits
your platform and compliance posture.

## Raw Kubernetes Secret

The simplest path: `kubectl create secret generic es-prod-us --from-literal=es-username=…
--from-literal=es-password=…`. The Secret lives in etcd (enable etcd encryption-at-rest).
Best for clusters where Secret material is managed out-of-band (CI, a vault export) and you
accept GitOps storing only references, not values.
Docs: https://kubernetes.io/docs/concepts/configuration/secret/

## Sealed Secrets (Bitnami)

Encrypt a Secret with the cluster's public cert so the *SealedSecret* (safe to commit to Git)
is decrypted only by the in-cluster controller: `kubeseal`. Good for GitOps without an external
secret store. Pin the `kubeseal` CLI to the controller's appVersion (the Helm chart version is a
different number). Re-seal per cluster (certs differ) and per namespace (strict-scoped by
default). See `examples/sealed-secrets/`.
Docs: https://github.com/bitnami-labs/sealed-secrets

## External Secrets Operator (ESO)

Sync secrets from AWS Secrets Manager / GCP Secret Manager / Azure Key Vault / HashiCorp Vault
into native K8s Secrets via an `ExternalSecret` + `SecretStore`. The cloud store is the source of
truth; ESO refreshes on an interval. Best when secrets already live in a managed store and you
want rotation. Map remote keys to the chart-expected data keys. Use the stable
`external-secrets.io/v1` API (`v1beta1` was removed at ESO v0.17.0). See
`examples/external-secrets/`.
Docs: https://external-secrets.io

## Vault Agent Injector

Inject secrets as files into the Pod via a Vault sidecar + pod annotations (no K8s Secret
object). Strongest isolation (secrets never touch etcd) but needs Vault + a custom container
command to read the injected file into the env the chart expects — pair with `useEnvFrom: false`
and an entrypoint shim. Best for Vault-centric orgs with strict no-etcd-secrets policies.
Docs: https://developer.hashicorp.com/vault/docs/platform/k8s/injector
