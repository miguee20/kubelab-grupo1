#!/usr/bin/env bash
# KubeLab - end-to-end verification of the platform against the course requirements.
# Run in the pve shell as root. Read-only by default:
#   bash verify-platform.sh
# With --destructive it also proves self-healing and persistence:
#   - deletes the web IngressRoute and waits for Argo CD to recreate it (CD-04)
#   - deletes postgres-0 and checks that the products are still there (PER-02, PER-03)
#   bash verify-platform.sh --destructive
set -uo pipefail

LB=10.10.10.200
DOMAIN=grupo1.lab
PASS=0; FAIL=0
ok()   { printf '  \e[32mPASS\e[0m %s\n' "$1"; PASS=$((PASS+1)); }
bad()  { printf '  \e[31mFAIL\e[0m %s\n' "$1"; FAIL=$((FAIL+1)); }
check() { if eval "$2" >/dev/null 2>&1; then ok "$1"; else bad "$1"; fi; }
http() { curl -s -o /dev/null -m 10 -w '%{http_code}' -H "Host: $1.$DOMAIN" "http://$LB$2"; }
section() { printf '\n\e[1m== %s\e[0m\n' "$1"; }

section "Infrastructure (INF)"
NODES=$(kubectl get nodes --no-headers 2>/dev/null)
[ "$(echo "$NODES" | grep -c ' Ready ')" -ge 4 ] && ok "INF-02/05 4 nodes Ready" || bad "INF-02/05 4 nodes Ready: $(echo "$NODES" | awk '{print $1"="$2}' | xargs)"
check "INF-05 control plane tainted NoSchedule" \
  "kubectl get node k3s-cp -o jsonpath='{.spec.taints[*].effect}' | grep -q NoSchedule"
CP_PODS=$(kubectl get pods -A --field-selector spec.nodeName=k3s-cp --no-headers \
  -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,OWNER:.metadata.ownerReferences[0].kind 2>/dev/null \
  | awk '$3!="DaemonSet" && $1!="kube-system"')
[ -z "$CP_PODS" ] && ok "INF-05 no application pods on k3s-cp" || bad "INF-05 pods on k3s-cp: $(echo "$CP_PODS" | awk '{print $1"/"$2}' | xargs)"
check "INF-06 Traefik has the MetalLB IP $LB" \
  "[ \"\$(kubectl -n traefik get svc traefik -o jsonpath='{.status.loadBalancer.ingress[0].ip}')\" = $LB ]"
check "ACC-02 Tailscale running on pve" "tailscale status"

section "GitOps (CD)"
APPS=$(kubectl -n argocd get applications --no-headers \
  -o custom-columns=N:.metadata.name,S:.status.sync.status,H:.status.health.status,P:.spec.syncPolicy.automated.prune,SH:.spec.syncPolicy.automated.selfHeal)
echo "$APPS" | awk '$2!="Synced"||$3!="Healthy"{f=1; print "    not healthy: "$1" "$2" "$3} END{exit f}' \
  && ok "CD-03 $(echo "$APPS" | wc -l) Applications Synced/Healthy" || bad "CD-03 some Applications are not Synced/Healthy"
echo "$APPS" | awk '$4!="true"||$5!="true"{f=1; print "    no prune/selfHeal: "$1} END{exit f}' \
  && ok "CD-04 every Application has automated prune + selfHeal" || bad "CD-04 prune/selfHeal missing"
[ "$(http argocd /healthz)" = 200 ] && ok "CD-02 argocd.$DOMAIN answers" || bad "CD-02 argocd.$DOMAIN"

section "Applications (APP)"
for d in api web; do
  AV=$(kubectl -n inventory get deploy $d -o jsonpath='{.status.availableReplicas}')
  [ "${AV:-0}" -ge 2 ] && ok "HA-01 $d has $AV available replicas" || bad "HA-01 $d has ${AV:-0} replicas"
done
IMAGES=$(kubectl -n inventory get deploy -o jsonpath='{range .items[*]}{.spec.template.spec.containers[*].image}{"\n"}{end}')
echo "$IMAGES" | grep -Evq ':[0-9a-f]{7}$' && bad "APP-05 image without a short SHA tag: $IMAGES" || ok "APP-05 images tagged with the short commit SHA ($(echo $IMAGES | xargs))"
check "APP-03/PER-03 PostgreSQL StatefulSet ready" \
  "[ \"\$(kubectl -n inventory get sts postgres -o jsonpath='{.status.readyReplicas}')\" = 1 ]"
[ "$(http api /health)" = 200 ] && ok "APP-01 api.$DOMAIN/health" || bad "APP-01 api.$DOMAIN/health"
[ "$(http api /products)" = 200 ] && ok "APP-01 api.$DOMAIN/products (CRUD list)" || bad "APP-01 api.$DOMAIN/products"
check "APP-01 api.$DOMAIN/metrics exposes http_requests_total" \
  "curl -s -m 10 -H 'Host: api.$DOMAIN' http://$LB/metrics | grep -q '^http_requests_total'"
[ "$(http app /)" = 200 ] && ok "APP-02 app.$DOMAIN" || bad "APP-02 app.$DOMAIN"
check "NET-04 db.$DOMAIN:5432 accepts TCP" "timeout 5 bash -c '</dev/tcp/$LB/5432'"

section "High availability (HA)"
HPA=$(kubectl -n inventory get hpa --no-headers -o custom-columns=N:.metadata.name,MIN:.spec.minReplicas,MAX:.spec.maxReplicas)
echo "$HPA" | awk '$2!=2||$3!=6{f=1} END{exit f||NR<2}' && ok "HA-04 HPA 2-6 for api and web" || bad "HA-04 HPA: $HPA"
check "HA-04 metrics-server answers (kubectl top)" "kubectl top nodes"
[ "$(kubectl -n inventory get pdb --no-headers | wc -l)" -ge 2 ] && ok "HA-03 PodDisruptionBudgets for api and web" || bad "HA-03 PDBs missing"
check "HA-05 load test script in the repository" \
  "curl -sfI https://raw.githubusercontent.com/miguee20/kubelab-grupo1/main/tests/load/k6-api.js"

section "Persistence (PER)"
check "PER-01 default StorageClass is nfs" \
  "kubectl get sc nfs -o jsonpath='{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}' | grep -q true"
PVC=$(kubectl get pvc -A --no-headers -o custom-columns=NS:.metadata.namespace,N:.metadata.name,S:.status.phase,SC:.spec.storageClassName)
echo "$PVC" | awk '$3!="Bound"||$4!="nfs"{f=1; print "    "$0} END{exit f}' \
  && ok "PER-02 $(echo "$PVC" | wc -l) PVCs Bound on nfs ($(echo "$PVC" | awk '{print $2}' | xargs))" || bad "PER-02 PVC problem"

section "Observability (OBS)"
[ "$(http prometheus /-/ready)" = 200 ] && ok "NET-03 prometheus.$DOMAIN" || bad "NET-03 prometheus.$DOMAIN"
[ "$(http grafana /api/health)" = 200 ] && ok "NET-03 grafana.$DOMAIN" || bad "NET-03 grafana.$DOMAIN"
TARGETS=$(curl -s -m 10 -H "Host: prometheus.$DOMAIN" "http://$LB/api/v1/targets" | python3 -c '
import json,sys
t=json.load(sys.stdin)["data"]["activeTargets"]
down=[x["labels"]["job"]+" "+x["scrapeUrl"] for x in t if x["health"]!="up"]
jobs=sorted({x["labels"]["job"] for x in t})
print(len(t), len(down), ",".join(jobs)); [print("    down:", d) for d in down]' 2>/dev/null)
read -r TOTAL DOWN JOBS <<<"$(echo "$TARGETS" | head -1)"
[ "${DOWN:-1}" = 0 ] && ok "OBS-01 $TOTAL Prometheus targets up ($JOBS)" || { bad "OBS-01 targets down"; echo "$TARGETS" | tail -n +2; }
for q in 'up{job="kubelab-pods",app="api"}' 'node_memory_MemAvailable_bytes' 'kube_deployment_status_replicas_available{namespace="inventory"}'; do
  N=$(curl -s -m 10 -G -H "Host: prometheus.$DOMAIN" "http://$LB/api/v1/query" --data-urlencode "query=$q" \
    | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["data"]["result"]))' 2>/dev/null)
  [ "${N:-0}" -gt 0 ] && ok "OBS-01 series found: $q ($N)" || bad "OBS-01 no series: $q"
done
DS=$(kubectl -n monitoring get ds -o custom-columns=N:.metadata.name,D:.status.desiredNumberScheduled,R:.status.numberReady --no-headers | grep promtail)
echo "$DS" | awk '$2==4&&$3==4{f=1} END{exit !f}' && ok "OBS-02 Promtail ready on 4/4 nodes" || bad "OBS-02 Promtail: $DS"
LOKI_NODES=$(kubectl get --raw "/api/v1/namespaces/monitoring/services/loki:3100/proxy/loki/api/v1/label/node_name/values" 2>/dev/null \
  | python3 -c 'import json,sys; print(" ".join(json.load(sys.stdin).get("data",[])))' 2>/dev/null)
[ "$(echo $LOKI_NODES | wc -w)" -ge 4 ] && ok "OBS-02 Loki has logs from: $LOKI_NODES" || bad "OBS-02 Loki nodes with logs: ${LOKI_NODES:-none}"
check "OBS-04 dashboard ConfigMap provisioned" "kubectl -n monitoring get cm grafana-dashboards"

section "Secrets (SEC)"
for s in inventory/inventory-secrets monitoring/grafana-secrets argocd/argocd-users; do
  check "SEC-02 Doppler-managed Secret $s" "kubectl -n ${s%/*} get secret ${s#*/}"
done
check "SEC-04 Doppler service token Secret present" "kubectl -n doppler-operator-system get secret doppler-token-secret"

if [ "${1:-}" = "--destructive" ]; then
  section "Self-healing (CD-04): delete the web IngressRoute"
  kubectl -n inventory delete ingressroute web >/dev/null
  for i in $(seq 1 36); do kubectl -n inventory get ingressroute web >/dev/null 2>&1 && break; sleep 5; done
  kubectl -n inventory get ingressroute web >/dev/null 2>&1 \
    && ok "CD-04 Argo CD recreated the IngressRoute after $((i*5)) s" || bad "CD-04 IngressRoute not recreated in 3 min"

  section "Persistence (PER-02): delete postgres-0"
  COUNT="kubectl -n inventory exec postgres-0 -- sh -c 'psql -U \"\$POSTGRES_USER\" -d \"\$POSTGRES_DB\" -tAc \"select count(*) from products\"'"
  BEFORE=$(eval "$COUNT" 2>/dev/null)
  kubectl -n inventory delete pod postgres-0 >/dev/null
  sleep 10
  kubectl -n inventory wait pod/postgres-0 --for=condition=Ready --timeout=300s >/dev/null
  AFTER=$(eval "$COUNT" 2>/dev/null)
  [ -n "$BEFORE" ] && [ "$BEFORE" = "$AFTER" ] \
    && ok "PER-02 products before/after deleting postgres-0: $BEFORE / $AFTER" || bad "PER-02 products before/after: ${BEFORE:-?} / ${AFTER:-?}"
fi

printf '\n\e[1mResult: %d passed, %d failed\e[0m\n' "$PASS" "$FAIL"
[ "$FAIL" = 0 ]
