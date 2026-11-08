#!/usr/bin/env bash
# Creates a local Kubernetes cluster with kind, builds the image, loads it and deploys the app.
# Needs: Docker, kind, kubectl.   Run from the repo root:  ./scripts/kind-up.sh
set -euo pipefail

CLUSTER=poc
IMAGE=todo-api:local

echo "==> 1/6 Creating kind cluster '$CLUSTER' (skipped if it exists)"
if ! kind get clusters | grep -qx "$CLUSTER"; then
  kind create cluster --config scripts/kind-config.yaml
fi
kubectl config use-context "kind-$CLUSTER"

echo "==> 2/6 Installing metrics-server (needed by the HPA and 'kubectl top')"
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
# kind's kubelets use self-signed certificates, so metrics-server must skip TLS checks (local only!)
kubectl -n kube-system patch deployment metrics-server --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]' 2>/dev/null || true

echo "==> 3/6 Building the Docker image $IMAGE"
docker build -t "$IMAGE" --build-arg APP_VERSION="local-$(date +%H%M%S)" .

echo "==> 4/6 Loading the image into the cluster nodes (no registry needed)"
kind load docker-image "$IMAGE" --name "$CLUSTER"

echo "==> 5/6 Deploying all manifests"
kubectl apply -k k8s/

echo "==> 6/6 Waiting for Postgres and the API to be ready"
kubectl -n todo rollout status statefulset/postgres --timeout=180s
kubectl -n todo rollout restart deployment/todo-api   # picks up a rebuilt image with the same tag
kubectl -n todo rollout status deployment/todo-api --timeout=180s

kubectl -n todo get pods -o wide
cat <<MSG

Done. Open the API with:
  kubectl -n todo port-forward svc/todo-api 8080:80
  then browse http://localhost:8080   (refresh: "host" changes = load balancing across Pods)

Demo scenarios:  ./scripts/demo.sh help
MSG
