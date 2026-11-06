#!/usr/bin/env bash
# KubeLab - Step 5: bootstrap Argo CD (run ONCE in the pve shell as root, from the clone in /root/kubelab-grupo1).
# This is the only manual kubectl apply in the project: it installs Argo CD and the root Application.
# From then on Argo CD manages itself and every other component from Git.
# Argo CD authenticates to the repository (required if it is private), so before the root Application
# this script creates, from Doppler:
#   - doppler-operator-system/doppler-token-secret: the Doppler service token (/root/.doppler-token, SEC-04)
#   - argocd/argocd-repo: repository credentials; afterwards the DopplerSecret argocd-repo keeps it in sync
set -euo pipefail

DIR=$(cd "$(dirname "$0")/../.." && pwd)
TOKEN=$(cat /root/.doppler-token)
doppler() { curl -fsS -u "${TOKEN}:" "https://api.doppler.com/v3/configs/config/secrets/download?format=json" \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['$1'])"; }

echo "==> 1/4 Doppler service token Secret (the only secret created by hand)"
kubectl create namespace doppler-operator-system --dry-run=client -o yaml | kubectl apply -f -
kubectl -n doppler-operator-system get secret doppler-token-secret >/dev/null 2>&1 || \
  kubectl -n doppler-operator-system create secret generic doppler-token-secret --from-file=serviceToken=/root/.doppler-token

echo "==> 2/4 Installing Argo CD"
kubectl apply --server-side --force-conflicts -k "${DIR}/k8s/argocd/install"
kubectl -n argocd rollout status deploy/argocd-server --timeout=600s
kubectl -n argocd rollout status deploy/argocd-repo-server --timeout=600s
kubectl -n argocd rollout status statefulset/argocd-application-controller --timeout=600s

echo "==> 3/4 Repository credentials for Argo CD (values from Doppler)"
kubectl -n argocd get secret argocd-repo >/dev/null 2>&1 || {
  kubectl -n argocd create secret generic argocd-repo \
    --from-literal=type="$(doppler ARGOCD_REPO_TYPE)" \
    --from-literal=url="$(doppler ARGOCD_REPO_URL)" \
    --from-literal=username="$(doppler ARGOCD_REPO_USERNAME)" \
    --from-literal=password="$(doppler GH_PAT)"
  kubectl -n argocd label secret argocd-repo argocd.argoproj.io/secret-type=repository
}

echo "==> 4/4 Creating the root Application (app of apps)"
kubectl apply -f "${DIR}/k8s/argocd/root.yaml"
echo "    waiting for the platform (MetalLB, Traefik, NFS, metrics-server)..."
for i in $(seq 1 60); do
  IP=$(kubectl -n traefik get svc traefik -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
  [ "$IP" = "10.10.10.200" ] && break
  sleep 10
done

echo
kubectl -n argocd get applications
echo
kubectl -n traefik get svc traefik
kubectl get storageclass
echo
echo "Argo CD initial admin password (replaced from Doppler by 06-argocd-users.sh):"
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
free -m
