#!/usr/bin/env bash
# KubeLab - Step 1: prepare the Proxmox host (run ONCE in the pve shell as root)
# - No-subscription repositories
# - Fixed internal network vmbr1 10.10.10.0/24 with NAT to vmbr0 (uplink)
# - Memory tuning (KSM, swappiness, HA services disabled)
# - NFS server for the cluster StorageClass
# - Tailscale as subnet router for 10.10.10.0/24
set -euo pipefail

echo "==> 1/6 No-subscription repositories"
CODENAME=$(. /etc/os-release; echo "$VERSION_CODENAME")
for f in /etc/apt/sources.list.d/pve-enterprise.sources /etc/apt/sources.list.d/ceph.sources; do
  if [ -f "$f" ] && ! grep -q '^Enabled:' "$f"; then echo "Enabled: false" >> "$f"; fi
done
cat > /etc/apt/sources.list.d/pve-no-subscription.sources <<EOF
Types: deb
URIs: http://download.proxmox.com/debian/pve
Suites: ${CODENAME}
Components: pve-no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF
apt-get update -qq
apt-get install -y -qq nfs-kernel-server iptables curl wget >/dev/null

echo "==> 2/6 Internal network vmbr1 (10.10.10.1/24) with NAT"
if ! grep -q 'iface vmbr1' /etc/network/interfaces; then
cat >> /etc/network/interfaces <<'EOF'

# KubeLab: fixed internal cluster network (independent of the uplink)
auto vmbr1
iface vmbr1 inet static
	address 10.10.10.1/24
	bridge-ports none
	bridge-stp off
	bridge-fd 0
	post-up   iptables -t nat -A POSTROUTING -s 10.10.10.0/24 -o vmbr0 -j MASQUERADE
	post-down iptables -t nat -D POSTROUTING -s 10.10.10.0/24 -o vmbr0 -j MASQUERADE
EOF
fi

cat > /etc/sysctl.d/99-kubelab.conf <<'EOF'
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
vm.swappiness = 10
EOF
sysctl -q --system
ifreload -a

echo "==> 3/6 Memory savings"
systemctl disable --now pve-ha-lrm pve-ha-crm >/dev/null 2>&1 || true
systemctl enable --now ksmtuned >/dev/null 2>&1 || true
# KSM starts merging earlier (when less than 40% is free)
if [ -f /etc/ksmtuned.conf ]; then
  sed -i 's/^#\?KSM_THRES_COEF=.*/KSM_THRES_COEF=40/' /etc/ksmtuned.conf
  systemctl restart ksmtuned || true
fi

echo "==> 4/6 NFS server for the cluster"
mkdir -p /srv/nfs/k8s
chmod 777 /srv/nfs/k8s
# async: the HDD acknowledges writes from the page cache instead of on every fsync.
# Much faster for SQLite (Grafana), PostgreSQL, Prometheus and Loki on a single HDD; a host
# power loss could lose the last seconds of writes, which is acceptable in this lab.
if ! grep -q '/srv/nfs/k8s' /etc/exports; then
  echo '/srv/nfs/k8s 10.10.10.0/24(rw,async,no_subtree_check,no_root_squash)' >> /etc/exports
fi
sed -i 's|/srv/nfs/k8s 10.10.10.0/24(rw,sync,|/srv/nfs/k8s 10.10.10.0/24(rw,async,|' /etc/exports
exportfs -ra
systemctl enable --now nfs-server >/dev/null

echo "==> 5/6 Enable snippets on local storage (for cloud-init)"
pvesm set local --content iso,vztmpl,backup,snippets,import

echo "==> 6/6 Tailscale"
if ! command -v tailscale >/dev/null; then
  curl -fsSL https://tailscale.com/install.sh | sh
fi
echo
echo ">>> Open the URL below on your laptop and sign in to Tailscale."
tailscale up --advertise-routes=10.10.10.0/24 --accept-dns=false --hostname=pve-grupo1

echo
echo "==> Done. Verification:"
ip -br a | grep -E 'vmbr0|vmbr1'
exportfs -v
tailscale status | head -3
free -m
