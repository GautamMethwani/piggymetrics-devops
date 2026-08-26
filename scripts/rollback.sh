#!/usr/bin/env bash
# Usage: scripts/rollback.sh <service>
set -euo pipefail
NS=piggymetrics
SERVICE="${1:?service name required}"
REPLICAS="${2:-1}"

log(){ echo "[rollback] $*"; }
current_color(){ kubectl -n "$NS" get svc "$SERVICE" -o jsonpath='{.spec.selector.color}'; }
opposite(){ [ "$1" = "blue" ] && echo green || echo blue; }

BAD="$(current_color)"
GOOD="$(opposite "$BAD")"
log "Current live=${BAD}, rolling back to ${GOOD}"

PREV=$(kubectl -n "$NS" get deployment "${SERVICE}-${GOOD}" -o jsonpath='{.spec.replicas}')
if [ "$PREV" = "0" ]; then
  kubectl -n "$NS" scale "deployment/${SERVICE}-${GOOD}" --replicas="$REPLICAS"
  kubectl -n "$NS" rollout status "deployment/${SERVICE}-${GOOD}" --timeout=180s
fi

kubectl -n "$NS" patch svc "$SERVICE" -p "{\"spec\":{\"selector\":{\"app\":\"${SERVICE}\",\"color\":\"${GOOD}\"}}}"
kubectl -n "$NS" scale "deployment/${SERVICE}-${BAD}" --replicas=0
log "Rolled back. ${SERVICE} live on ${GOOD}"
