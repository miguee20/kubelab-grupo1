#!/usr/bin/env bash
# KubeLab - Step 6: Argo CD passwords from Doppler (run in the pve shell as root; safe to re-run)
# - ARGOCD_ADMIN_PASSWORD  -> admin (replaces the random initial password)
# - ARGOCD_VIEWER_PASSWORD -> docente, read-only account defined in k8s/argocd/install (ACC-03)
# Doppler syncs both values into the Secret argocd/argocd-users. Argo CD only stores bcrypt
# hashes, so this script hashes them with the argocd CLI inside the argocd-server pod and
# writes the hashes into argocd-secret. The plain values never appear on screen.
set -euo pipefail

get() { kubectl -n argocd get secret argocd-users -o jsonpath="{.data.$1}" | base64 -d; }
hash() { kubectl -n argocd exec deploy/argocd-server -- argocd account bcrypt --password "$1"; }

echo "==> Waiting for the Doppler-managed Secret argocd/argocd-users"
for i in $(seq 1 30); do kubectl -n argocd get secret argocd-users >/dev/null 2>&1 && break; sleep 10; done

ADMIN=$(get ARGOCD_ADMIN_PASSWORD)
VIEWER=$(get ARGOCD_VIEWER_PASSWORD)
[ -n "$ADMIN" ] && [ -n "$VIEWER" ] || { echo "Missing ARGOCD_ADMIN_PASSWORD or ARGOCD_VIEWER_PASSWORD in Doppler"; exit 1; }

echo "==> Hashing passwords and updating argocd-secret"
NOW=$(date -u +%FT%TZ)
kubectl -n argocd patch secret argocd-secret --type merge -p "{\"stringData\":{
  \"admin.password\":\"$(hash "$ADMIN")\",\"admin.passwordMtime\":\"$NOW\",
  \"accounts.docente.password\":\"$(hash "$VIEWER")\",\"accounts.docente.passwordMtime\":\"$NOW\"}}"
unset ADMIN VIEWER

# The random initial password is no longer valid; Argo CD recommends deleting it
kubectl -n argocd delete secret argocd-initial-admin-secret --ignore-not-found

echo "==> Done. Log in at http://argocd.grupo1.lab as admin or docente (read-only)."
