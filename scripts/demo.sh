#!/usr/bin/env bash
# Demo scenarios for presenting the POC. Run the cluster first: ./scripts/kind-up.sh
# Usage: ./scripts/demo.sh <scenario>
set -euo pipefail
NS=todo
APP=deployment/todo-api

pf_start() {   # opens the Service on localhost:8080 in the background
  kubectl -n "$NS" port-forward svc/todo-api 8080:80 >/dev/null 2>&1 &
  PF_PID=$!; trap 'kill $PF_PID 2>/dev/null || true' EXIT; sleep 3
}

case "${1:-help}" in
  status)          # everything in the namespace
    kubectl -n "$NS" get all,pvc,configmap,secret,hpa,pdb
    ;;

  loadbalance)     # 10 requests -> answered by different Pods
    # port-forward always sticks to ONE Pod, so call the Service from a Pod inside the cluster.
    kubectl -n "$NS" run "lb-$RANDOM" --rm -i --restart=Never --quiet --labels=demo=lb \
      --image=curlimages/curl --command -- \
      sh -c 'for i in $(seq 1 10); do curl -s http://todo-api/ | grep -o "\"host\":\"[^\"]*\""; done'
    ;;

  selfheal-delete) # delete a Pod -> a new one is created automatically
    POD=$(kubectl -n "$NS" get pods -l app=todo-api -o jsonpath='{.items[0].metadata.name}')
    echo "Deleting $POD ..."
    kubectl -n "$NS" delete pod "$POD" --wait=false
    kubectl -n "$NS" get pods -l app=todo-api -w
    ;;

  selfheal-crash)  # the app process crashes -> the container is restarted (RESTARTS goes up)
    pf_start
    curl -s -X POST http://localhost:8080/api/crash; echo
    kubectl -n "$NS" get pods -l app=todo-api -w
    ;;

  scale)           # manual scaling (the HPA will later move it back inside 3..8)
    kubectl -n "$NS" scale "$APP" --replicas="${2:-5}"
    kubectl -n "$NS" get pods -l app=todo-api -w
    ;;

  config)          # change the ConfigMap -> restart -> new greeting, same image
    kubectl -n "$NS" patch configmap todo-api-config --type merge \
      -p "{\"data\":{\"App__Greeting\":\"Updated at $(date +%H:%M:%S) without rebuilding the image\"}}"
    kubectl -n "$NS" rollout restart "$APP"
    kubectl -n "$NS" rollout status "$APP"
    pf_start; curl -s http://localhost:8080/; echo
    ;;

  rollout)         # zero-downtime rolling update to a new image version
    VERSION="v$(date +%H%M%S)"
    docker build -t "todo-api:$VERSION" --build-arg APP_VERSION="$VERSION" .
    kind load docker-image "todo-api:$VERSION" --name poc
    kubectl -n "$NS" set image "$APP" api="todo-api:$VERSION"
    kubectl -n "$NS" rollout status "$APP"
    kubectl -n "$NS" rollout history "$APP"
    ;;

  bad-rollout)     # deploy an image that does not exist -> old Pods keep serving (maxUnavailable: 0)
    kubectl -n "$NS" set image "$APP" api=todo-api:does-not-exist
    sleep 15
    kubectl -n "$NS" get pods -l app=todo-api
    echo; echo "New Pod is stuck in ErrImagePull/ImagePullBackOff, the 3 old Pods still serve traffic."
    echo "Fix it with:  ./scripts/demo.sh rollback"
    ;;

  rollback)        # go back to the previous version
    kubectl -n "$NS" rollout undo "$APP"
    kubectl -n "$NS" rollout status "$APP"
    ;;

  hpa)             # generate CPU load -> HPA adds Pods (watch for ~2 minutes)
    for i in 1 2 3 4 5 6; do
      kubectl -n "$NS" run "load-$i-$RANDOM" --restart=Never --quiet --labels=demo=load \
        --image=curlimages/curl --command -- \
        sh -c 'for j in $(seq 1 12); do curl -s "http://todo-api/api/stress?seconds=20" >/dev/null; done'
    done
    echo "Watching the HPA (Ctrl+C to stop). TARGETS goes above 60%, then REPLICAS grows."
    kubectl -n "$NS" get hpa todo-api -w
    ;;

  hpa-clean)       # remove the load generator Pods
    kubectl -n "$NS" delete pod -l demo=load --ignore-not-found
    ;;

  persistence)     # data survives deleting the Postgres Pod (PersistentVolumeClaim)
    pf_start
    curl -s -X POST http://localhost:8080/api/todos -H "Content-Type: application/json" \
      -d '{"title":"I must survive","isDone":false}'; echo
    kill $PF_PID 2>/dev/null || true
    kubectl -n "$NS" delete pod postgres-0
    kubectl -n "$NS" wait --for=condition=Ready pod/postgres-0 --timeout=120s
    sleep 10; pf_start
    curl -s http://localhost:8080/api/todos | grep -o '"title":"I must survive"' && echo "Data is still there"
    ;;

  debug)           # the troubleshooting commands you use every day
    POD=$(kubectl -n "$NS" get pods -l app=todo-api -o jsonpath='{.items[0].metadata.name}')
    kubectl -n "$NS" describe pod "$POD" | tail -20
    kubectl -n "$NS" logs "$POD" --tail=20
    kubectl -n "$NS" get endpoints todo-api
    kubectl top pods -n "$NS" || echo "(metrics not ready yet, wait a minute)"
    ;;

  *)
    cat <<HELP
Scenarios:
  status            everything running in the namespace
  loadbalance       requests spread over several Pods
  selfheal-delete   delete a Pod, Kubernetes recreates it
  selfheal-crash    crash the app, Kubernetes restarts it
  scale [n]         scale manually to n Pods
  config            change ConfigMap value without rebuilding
  rollout           zero-downtime rolling update to a new version
  bad-rollout       broken image: old version keeps serving
  rollback          return to the previous version
  hpa / hpa-clean   CPU load makes the autoscaler add Pods
  persistence       database data survives a Pod restart
  debug             describe / logs / endpoints / top
HELP
    ;;
esac
