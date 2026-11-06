#!/usr/bin/env bash
# Git credential helper for the repository on the pve host (required while it is private).
# Reads GH_PAT from Doppler with the service token in /root/.doppler-token, so no GitHub
# token is ever written to disk or to .git/config.
#   git config credential.helper /root/kubelab-grupo1/scripts/proxmox/git-credential-doppler.sh
[ "${1:-}" = "get" ] || exit 0
TOKEN=$(cat /root/.doppler-token)
PAT=$(curl -fsS -u "${TOKEN}:" "https://api.doppler.com/v3/configs/config/secrets/download?format=json" \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["GH_PAT"])')
echo "username=x-access-token"
echo "password=${PAT}"
