#!/usr/bin/env bash
# KubeLab - Step 4: host memory tuning for a 6 GB machine (run in the pve shell as root)
# - zram swap on the host: compressed swap in RAM, used before the slow HDD swap
# - virtio-balloon device on every VM (balloon = memory, so guests never shrink):
#   with free page reporting, pages freed inside the guests go back to the host
# VMs are restarted one by one; the cluster keeps running.
set -euo pipefail

declare -A MEM=( [101]=1024 [102]=1152 [103]=1152 [104]=1152 )
declare -A NAME=( [101]=k3s-cp [102]=k3s-w1 [103]=k3s-w2 [104]=k3s-w3 )

echo "==> 1/2 zram swap on the host"
apt-get install -y -qq zram-tools >/dev/null
cat > /etc/default/zramswap <<'EOF'
ALGO=zstd
PERCENT=50
PRIORITY=100
EOF
systemctl restart zramswap
swapon --show

echo "==> 2/2 Balloon device on the VMs (rolling restart)"
for ID in 104 103 102 101; do
  CUR=$(qm config $ID | awk '/^balloon:/{print $2}')
  if [ "$CUR" = "${MEM[$ID]}" ]; then echo "   ${NAME[$ID]} already configured"; continue; fi
  qm set $ID --balloon ${MEM[$ID]} >/dev/null
  echo "   restarting ${NAME[$ID]}..."
  qm shutdown $ID --timeout 120 || qm stop $ID
  qm start $ID
  sleep 45   # give the kubelet time to report the restart before polling
  for i in $(seq 1 40); do
    STATUS=$(kubectl get node ${NAME[$ID]} --no-headers 2>/dev/null | awk '{print $2}')
    [ "$STATUS" = "Ready" ] && break
    sleep 6
  done
  echo "   ${NAME[$ID]}: ${STATUS:-unknown}"
done

echo
kubectl get nodes
free -m
