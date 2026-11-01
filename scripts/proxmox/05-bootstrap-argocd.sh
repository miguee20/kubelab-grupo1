#!/usr/bin/env bash
# KubeLab - Step 5: bootstrap Argo CD (run ONCE in the pve shell as root).
# This is the only manual kubectl apply in the project: it installs Argo CD and the
# root Application. From then on Argo CD manages itself and every other component from Git.
set -euo pipefail

REPO=https://github.com/miguee20/kubelab-grupo1
RAW=https://raw.githubusercontent.com/miguee20/kubelab-grupo1/main

command -v git >/dev/null || apt-get install -y -qq git >/dev/null

echo "==> 1/3 Installing Argo CD"
kubectl apply --server-side --force-conflicts -k "${REPO}//k8s/argocd/install?ref=main"
kubectl -n argocd rollout status deploy/argocd-server --timeout=600s
kubectl -n argocd rollout status deploy/argocd-repo-server --timeout=600s
kubectl -n argocd rollout status statefulset/argocd-application-controller --timeout=600s

echo "==> 2/3 Creating the root Application (app of apps)"
kubectl apply -f "${RAW}/k8s/argocd/root.yaml"

echo "==> 3/3 Waiting for the platform (MetalLB, Traefik, NFS, metrics-server)..."
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
echo "Argo CD admin password:"
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
free -m
