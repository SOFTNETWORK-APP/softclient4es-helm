# Sealed Secrets examples (Story 16.3)

These two `SealedSecret` manifests show the **shape** the chart expects for a
GitOps-friendly secret workflow with [Bitnami Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets).

> ⚠️ **They are NON-FUNCTIONAL placeholders.** The `encryptedData` was sealed with an
> example key and **will not decrypt** in your cluster. You **must re-seal** every
> SealedSecret with **your** controller's public cert. SealedSecrets are sealed
> per-controller and (by default) per-namespace.

| File | Materializes Secret | Chart reference |
|---|---|---|
| `es-credentials.sealedsecret.yaml` | `es-prod-us` (keys `es-auth-method`, `es-username`, `es-password`) | `sidecars[].elasticsearch.credentialsSecretName` |
| `sidecar-auth.sealedsecret.yaml` | `prod-us-arrow-auth` (key `arrow-bearer-token`) | `sidecars[].auth.credentialsSecretName` (feeds BOTH sides) |

## Re-seal with your controller

```sh
# 1. Install the controller (repo MOVED bitnami-labs -> bitnami):
helm repo add sealed-secrets https://bitnami.github.io/sealed-secrets
helm upgrade --install sealed-secrets sealed-secrets/sealed-secrets -n kube-system

# 2. Re-seal the ES credentials Secret for YOUR cluster + namespace:
kubectl create secret generic es-prod-us --namespace <your-ns> \
  --from-literal=es-auth-method=basic \
  --from-literal=es-username=elastic \
  --from-literal=es-password='<your-password>' \
  --dry-run=client -o yaml \
| kubeseal --controller-name sealed-secrets --controller-namespace kube-system \
    --format yaml > es-credentials.sealedsecret.yaml

# 3. Re-seal the sidecar/federation auth Secret (ONE Secret feeds both sides):
kubectl create secret generic prod-us-arrow-auth --namespace <your-ns> \
  --from-literal=arrow-bearer-token='<token>' \
  --dry-run=client -o yaml \
| kubeseal --controller-name sealed-secrets --controller-namespace kube-system \
    --format yaml > sidecar-auth.sealedsecret.yaml

kubectl apply -f es-credentials.sealedsecret.yaml -f sidecar-auth.sealedsecret.yaml
```

## Gotchas

- **`kubeseal` CLI version ≠ Helm chart version.** Chart `2.16.2` bundles controller/CLI
  appVersion `0.27.2`. Building the CLI URL from the chart version 404s. Pin the CLI to the
  controller's **appVersion**.
- **Namespace scope.** A strict-scoped SealedSecret is bound to an exact `name + namespace`.
  Deploying the chart into a different namespace requires re-sealing with `--namespace <ns>`,
  or sealing `--scope namespace-wide` / `--scope cluster-wide` with the matching
  `sealedsecrets.bitnami.com/namespace-wide` / `cluster-wide` annotation on the source Secret.
- **A wrong namespace fails SILENTLY** — the Secret never materializes, the chart's
  `optional: true` `secretKeyRef`s no-op, and the federation CrashLoops at boot with a
  `FlightCredentials`/`validate()` error. See the chart README "Secrets, TLS & Ingress".
