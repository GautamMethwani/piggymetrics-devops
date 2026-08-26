#!/usr/bin/env bash
# Usage: scripts/blue-green-switch.sh <service> <image-tag> [replicas]
set -euo pipefail
NS=piggymetrics
SERVICE="${1:?service name required}"
TAG="${2:?image tag required}"
REPLICAS="${3:-1}"

log(){ echo "[blue-green] $*"; }
current_color(){ kubectl -n "$NS" get svc "$SERVICE" -o jsonpath='{.spec.selector.color}'; }
opposite(){ [ "$1" = "blue" ] && echo green || echo blue; }

ACTIVE="$(current_color)"
IDLE="$(opposite "$ACTIVE")"
IMAGE="piggymetrics-${SERVICE}:${TAG}"

log "Active=$ACTIVE, deploying $IMAGE to idle=$IDLE"

log "Loading image into Kind cluster"
kind load docker-image "$IMAGE" --name piggymetrics

log "Updating ${SERVICE}-${IDLE} image and scaling to ${REPLICAS}"
kubectl -n "$NS" set image "deployment/${SERVICE}-${IDLE}" "${SERVICE}=${IMAGE}"
kubectl -n "$NS" scale "deployment/${SERVICE}-${IDLE}" --replicas="$REPLICAS"

log "Waiting for rollout"
if ! kubectl -n "$NS" rollout status "deployment/${SERVICE}-${IDLE}" --timeout=180s; then
  log "FAILED health check. Scaling ${IDLE} back to 0. Production untouched."
  kubectl -n "$NS" scale "deployment/${SERVICE}-${IDLE}" --replicas=0
  exit 1
fi

log "Pointing preview at ${IDLE} and smoke testing"
kubectl -n "$NS" patch svc "${SERVICE}-preview" -p "{\"spec\":{\"selector\":{\"app\":\"${SERVICE}\",\"color\":\"${IDLE}\"}}}"

PORT=$(kubectl -n "$NS" get svc "${SERVICE}-preview" -o jsonpath='{.spec.ports[0].port}')
CTXPATH=""
case "$SERVICE" in
  account-service) CTXPATH="/accounts" ;;
  auth-service) CTXPATH="/uaa" ;;
  statistics-service) CTXPATH="/statistics" ;;
  notification-service) CTXPATH="/notifications" ;;
  gateway) CTXPATH="" ;;
esac

# Any real HTTP response (200, 401, etc.) means the app is alive and
# routing correctly. Only a connection failure ("000" / no response)
# means the new version is genuinely broken. /health requires OAuth2
# in this app, so 401 is expected and healthy, not a failure.
if ! kubectl -n "$NS" run "smoke-${SERVICE}-$$" --rm -i --restart=Never --image=curlimages/curl:8.8.0 --command -- \
  sh -c "code=\$(curl -s --max-time 5 --retry 8 --retry-delay 3 -o /dev/null -w '%{http_code}' http://${SERVICE}-preview:${PORT}${CTXPATH}/health); echo \"got \$code\"; [ \"\$code\" != '000' ] && [ -n \"\$code\" ]"; then
  log "Smoke test FAILED. Scaling ${IDLE} back to 0. Production untouched."
  kubectl -n "$NS" scale "deployment/${SERVICE}-${IDLE}" --replicas=0
  exit 1
fi

log "Smoke test passed. Switching live traffic: ${SERVICE} -> ${IDLE}"
kubectl -n "$NS" patch svc "$SERVICE" -p "{\"spec\":{\"selector\":{\"app\":\"${SERVICE}\",\"color\":\"${IDLE}\"}}}"

log "Scaling down old color ${ACTIVE} to 0 (kept warm for rollback)"
kubectl -n "$NS" scale "deployment/${SERVICE}-${ACTIVE}" --replicas=0

log "Done. ${SERVICE} live on ${IDLE} (${IMAGE})"
