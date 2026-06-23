#!/usr/bin/env bash
# Story 16.5 — install the Bitnami SealedSecrets controller into a kind cluster, then seal an
# Elasticsearch-auth Secret with the IN-CLUSTER controller certificate and apply it, so the
# controller materializes a real K8s Secret the chart can reference. Used by the
# `install-secrets` (sealed-secrets) job of .github/workflows/federation-helm.yml.
#
# Usage:  install-sealed-secrets.sh <secret-name>
#   secret-name : the name of the Secret the controller will materialize (chart references this
#                 via sidecars[0].elasticsearch.credentialsSecretName), e.g. "es-creds".
#
# Why re-seal in CI (project_sealed_secrets_review_gotchas):
#   * The committed examples/sealed-secrets/*.yaml are NON-FUNCTIONAL placeholders — a SealedSecret
#     is decryptable ONLY by the specific controller instance that issued the cert. We therefore
#     create a fresh plaintext Secret, `kubeseal` it with the live cluster's cert, and apply.
#   * The kubeseal CLI version is pinned to the controller chart appVersion (NOT the chart version).
set -euo pipefail

SECRET_NAME="${1:?usage: install-sealed-secrets.sh <secret-name>}"

# Pin the controller chart + kubeseal CLI so the CLI/controller versions match (gotcha:
# kubeseal CLI version must equal the controller appVersion, not the Helm chart version).
SEALED_SECRETS_CHART_VERSION="2.16.2"   # helm chart version
KUBESEAL_VERSION="0.27.2"               # == controller appVersion of chart 2.16.2

# 1. Install the controller (repo moved bitnami-labs -> bitnami.github.io).
helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets >/dev/null 2>&1 || \
  helm repo add sealed-secrets https://bitnami.github.io/sealed-secrets
helm repo update sealed-secrets
helm upgrade --install sealed-secrets sealed-secrets/sealed-secrets \
  --namespace kube-system \
  --version "${SEALED_SECRETS_CHART_VERSION}" \
  --set fullnameOverride=sealed-secrets-controller \
  --wait --timeout 180s

# 2. Install the matching kubeseal CLI.
curl -sSL "https://github.com/bitnami-labs/sealed-secrets/releases/download/v${KUBESEAL_VERSION}/kubeseal-${KUBESEAL_VERSION}-linux-amd64.tar.gz" \
  | tar -xz kubeseal
sudo install -m 0755 kubeseal /usr/local/bin/kubeseal
rm -f kubeseal

# 3. Wait for the controller to be Ready, then fetch its public cert.
kubectl rollout status deployment/sealed-secrets-controller -n kube-system --timeout=180s
kubeseal --controller-name=sealed-secrets-controller --controller-namespace=kube-system \
  --fetch-cert > /tmp/sealed-secrets-cert.pem

# 4. Build a plaintext ES-auth Secret (matching the 16.3 es-* key contract), seal it with the
#    live cert, and apply the SealedSecret (the plaintext Secret is NEVER applied to the cluster).
kubectl create secret generic "${SECRET_NAME}" \
  --dry-run=client -o yaml \
  --from-literal=es-auth-method=basic \
  --from-literal=es-username=elastic \
  --from-literal=es-password=changeme \
  | kubeseal --cert /tmp/sealed-secrets-cert.pem --format yaml \
  | kubectl apply -f -

# 5. Wait for the controller to materialize the real Secret from the SealedSecret.
for _ in $(seq 1 30); do
  if kubectl get secret "${SECRET_NAME}" >/dev/null 2>&1; then
    echo "SealedSecrets materialized Secret '${SECRET_NAME}'."
    exit 0
  fi
  sleep 2
done

echo "::error::SealedSecrets controller did not materialize Secret '${SECRET_NAME}' in time" >&2
kubectl get sealedsecret,secret 2>/dev/null || true
exit 1
