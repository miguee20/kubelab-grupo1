#!/usr/bin/env bash
# KubeLab - Paso 1: preparar el host Proxmox (se ejecuta UNA vez en la shell de pve como root)
# - Repos sin suscripción
# - Red interna fija vmbr1 10.10.10.0/24 con NAT hacia vmbr0 (uplink)
# - Ajustes de memoria (KSM, swappiness, sin servicios HA)
# - Servidor NFS para la StorageClass del clúster
# - Tailscale como subnet router de 10.10.10.0/24
set -euo pipefail

echo "==> 1/6 Repositorios sin suscripción"
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

echo "==> 2/6 Red interna vmbr1 (10.10.10.1/24) con NAT"
if ! grep -q 'iface vmbr1' /etc/network/interfaces; then
cat >> /etc/network/interfaces <<'EOF'

# KubeLab: red interna fija del clúster (no depende del uplink)
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

echo "==> 3/6 Ahorro de memoria"
systemctl disable --now pve-ha-lrm pve-ha-crm >/dev/null 2>&1 || true
systemctl enable --now ksmtuned >/dev/null 2>&1 || true
# KSM empieza a deduplicar antes (cuando queda menos del 40% libre)
if [ -f /etc/ksmtuned.conf ]; then
  sed -i 's/^#\?KSM_THRES_COEF=.*/KSM_THRES_COEF=40/' /etc/ksmtuned.conf
  systemctl restart ksmtuned || true
fi

echo "==> 4/6 Servidor NFS para el clúster"
mkdir -p /srv/nfs/k8s
chmod 777 /srv/nfs/k8s
if ! grep -q '/srv/nfs/k8s' /etc/exports; then
  echo '/srv/nfs/k8s 10.10.10.0/24(rw,sync,no_subtree_check,no_root_squash)' >> /etc/exports
fi
exportfs -ra
systemctl enable --now nfs-server >/dev/null

echo "==> 5/6 Habilitar snippets en el storage local (para cloud-init)"
pvesm set local --content iso,vztmpl,backup,snippets,import

echo "==> 6/6 Tailscale"
if ! command -v tailscale >/dev/null; then
  curl -fsSL https://tailscale.com/install.sh | sh
fi
echo
echo ">>> Abre en tu laptop la URL que aparece abajo e inicia sesión en Tailscale."
tailscale up --advertise-routes=10.10.10.0/24 --accept-dns=false --hostname=pve-grupo1

echo
echo "==> Listo. Verificación:"
ip -br a | grep -E 'vmbr0|vmbr1'
exportfs -v
tailscale status | head -3
free -m
