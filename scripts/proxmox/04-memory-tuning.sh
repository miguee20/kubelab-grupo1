#!/usr/bin/env bash
# KubeLab - Step 4: memory tuning for a 6 GB host (run in the pve shell as root; safe to re-run)
# - zram swap on the host: compressed swap in RAM, used before the slow HDD swap
# - virtio-balloon device on every VM (balloon = memory, so guests never shrink):
#   with free page reporting, pages freed inside the guests go back to the host
# - every node gets 1408 MB (the host overcommits ~1 GB, covered by KSM and host zram)
# - control plane: unused k3s controllers disabled, GOGC=50
# Only VMs whose settings change are restarted, one at a time.
set -euo pipefail

declare -A MEM=( [101]=1408 [102]=1408 [103]=1408 [104]=1408 )
declare -A NAME=( [101]=k3s-cp [102]=k3s-w1 [103]=k3s-w2 [104]=k3s-w3 )
CP=10.10.10.11
SSH="ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5"

echo "==> 1/3 zram swap on the host"
command -v zramctl >/dev/null && dpkg -s zram-tools >/dev/null 2>&1 || apt-get install -y -qq zram-tools >/dev/null
cat > /etc/default/zramswap <<'EOF'
ALGO=zstd
PERCENT=50
PRIORITY=100
EOF
systemctl restart zramswap
swapon --show

echo "==> 2/3 k3s server tuning on k3s-cp (applied on its next restart)"
$SSH kube@$CP 'sudo mkdir -p /etc/rancher/k3s && printf "disable-cloud-controller: true\ndisable-helm-controller: true\ndisable-network-policy: true\n" | sudo tee /etc/rancher/k3s/config.yaml >/dev/null
  grep -q "^GOGC=" /etc/systemd/system/k3s.service.env 2>/dev/null || echo GOGC=50 | sudo tee -a /etc/systemd/system/k3s.service.env >/dev/null' \
  || echo "   (k3s-cp not reachable over SSH right now; settings already applied earlier)"

echo "==> 3/3 VM memory and balloon device (rolling restart only where needed)"
for ID in 104 103 102 101; do
  CUR_MEM=$(qm config $ID | awk '/^memory:/{print $2}')
  CUR_BAL=$(qm config $ID | awk '/^balloon:/{print $2}')
  if [ "$CUR_MEM" = "${MEM[$ID]}" ] && [ "$CUR_BAL" = "${MEM[$ID]}" ]; then
    echo "   ${NAME[$ID]} already configured (${MEM[$ID]} MB)"; continue
  fi
  qm set $ID --memory ${MEM[$ID]} --balloon ${MEM[$ID]} >/dev/null
  echo "   restarting ${NAME[$ID]} with ${MEM[$ID]} MB..."
  qm shutdown $ID --timeout 120 || qm stop $ID
  qm start $ID
  sleep 45   # give the kubelet time to report the restart before polling
  STATUS=""
  for i in $(seq 1 60); do
    STATUS=$(kubectl get node ${NAME[$ID]} --no-headers 2>/dev/null | awk '{print $2}')
    [ "$STATUS" = "Ready" ] && break
    sleep 6
  done
  echo "   ${NAME[$ID]}: ${STATUS:-unknown}"
done

echo
kubectl get nodes
$SSH kube@$CP 'echo "k3s-cp:"; free -m' || true
echo "pve host:"; free -m
