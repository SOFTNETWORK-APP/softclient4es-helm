#!/usr/bin/env bash
# Story 16.5 — deploy single-node Elasticsearch container(s) into a kind cluster, one per
# federation sidecar, reachable at the in-cluster Service name the install job overrides each
# sidecars[].elasticsearch.url to. Used by .github/workflows/federation-helm.yml.
#
# Usage:  deploy-es.sh <topology> <es-version-list>
#   topology         : single-cluster | three-region | heterogeneous-ready | es-version | secrets
#   es-version-list  : comma-separated ES major versions, e.g. "8" or "8,8,9"
#
# Service names (must match the --set sidecars[N].elasticsearch.url=... in the install jobs):
#   * 1-ES topologies (single-cluster / es-version / secrets) -> Service "es"
#   * 3-ES topologies (three-region / heterogeneous-ready)    -> "es-us-east-1", "es-eu-west-1",
#                                                                "es-ap-south-1" (order = list order)
#
# Each ES runs single-node, security disabled, small heap (fits the 7 GB GitHub runner).
# `vm.max_map_count=262144` MUST already be set on the runner (the workflow does this).
set -euo pipefail

TOPOLOGY="${1:?usage: deploy-es.sh <topology> <es-version-list>}"
ES_LIST="${2:?usage: deploy-es.sh <topology> <es-version-list>}"

# ES major version -> full image coordinate (CLAUDE.md ES Version Matrix).
es_image() {
  case "$1" in
    6) echo "docker.elastic.co/elasticsearch/elasticsearch:6.8.23" ;;
    7) echo "docker.elastic.co/elasticsearch/elasticsearch:7.17.29" ;;
    8) echo "docker.elastic.co/elasticsearch/elasticsearch:8.18.3" ;;
    9) echo "docker.elastic.co/elasticsearch/elasticsearch:9.0.3" ;;
    *) echo "unsupported ES version: $1" >&2; exit 1 ;;
  esac
}

# Resolve the Service names for this topology, positionally aligned with the ES list.
case "$TOPOLOGY" in
  three-region|heterogeneous-ready)
    NAMES=(es-us-east-1 es-eu-west-1 es-ap-south-1)
    ;;
  single-cluster|es-version|secrets)
    NAMES=(es)
    ;;
  *)
    echo "unsupported topology: $TOPOLOGY" >&2; exit 1 ;;
esac

# Split the comma-separated version list into an array.
IFS=',' read -r -a VERSIONS <<< "$ES_LIST"

if [ "${#VERSIONS[@]}" -gt "${#NAMES[@]}" ]; then
  echo "::error::deploy-es.sh: ${#VERSIONS[@]} ES versions but only ${#NAMES[@]} service name(s) for topology $TOPOLOGY" >&2
  exit 1
fi

# Pre-pull the ES images on the host and load them into the kind cluster: the node's
# containerd would otherwise pull from docker.elastic.co in-cluster, and the ~1.4 GB
# ES 8/9 images repeatedly hit ImagePullBackOff inside the 300s wait on GitHub runners.
# The Deployment's tagged image + default IfNotPresent then uses the loaded copy, no pull.
KIND_CLUSTER="$(kind get clusters | head -n 1)"
for v in $(printf '%s\n' "${VERSIONS[@]}" | sort -u); do
  image="$(es_image "$v")"
  echo "Pre-pulling ${image} and loading it into kind cluster '${KIND_CLUSTER}'"
  docker pull "$image"
  kind load docker-image "$image" --name "$KIND_CLUSTER"
done

deploy_one() {
  local name="$1" version="$2" image
  image="$(es_image "$version")"
  echo "Deploying Elasticsearch ${version} as Service '${name}' (${image})"
  kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${name}
  labels:
    app: ${name}
    role: ci-elasticsearch
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${name}
  template:
    metadata:
      labels:
        app: ${name}
        role: ci-elasticsearch
    spec:
      containers:
        - name: elasticsearch
          image: ${image}
          env:
            - name: discovery.type
              value: single-node
            - name: xpack.security.enabled
              value: "false"
            - name: ES_JAVA_OPTS
              value: "-Xms512m -Xmx512m"
            # ES 8/9 default to HTTPS + security ON; the env above disables it, but be explicit.
            - name: xpack.security.http.ssl.enabled
              value: "false"
          ports:
            - containerPort: 9200
          readinessProbe:
            httpGet:
              path: /_cluster/health?wait_for_status=yellow&timeout=1s
              port: 9200
            initialDelaySeconds: 20
            periodSeconds: 5
            failureThreshold: 30
          resources:
            requests:
              memory: 1Gi
            limits:
              memory: 1536Mi
---
apiVersion: v1
kind: Service
metadata:
  name: ${name}
  labels:
    role: ci-elasticsearch
spec:
  selector:
    app: ${name}
  ports:
    - port: 9200
      targetPort: 9200
EOF
}

i=0
for v in "${VERSIONS[@]}"; do
  deploy_one "${NAMES[$i]}" "$v"
  i=$((i + 1))
done

# Wait for every ES Deployment to become Available before the install job starts the sidecars
# (FACT D: the federation only goes Ready once every downstream is reachable).
for ((j = 0; j < ${#VERSIONS[@]}; j++)); do
  echo "Waiting for Elasticsearch Deployment '${NAMES[$j]}' to be Available..."
  kubectl wait --for=condition=Available "deployment/${NAMES[$j]}" --timeout=300s
done

echo "All Elasticsearch instances ready for topology '${TOPOLOGY}'."
