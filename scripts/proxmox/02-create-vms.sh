#!/usr/bin/env bash
# KubeLab - Step 2: Debian 13 cloud-init template and the 4 cluster VMs
# Run in the pve shell as root, after 01-host-setup.sh
set -euo pipefail

TPL_ID=9000
IMG_URL="https://cloud.debian.org/images/cloud/trixie/latest/debian-13-generic-amd64.qcow2"
IMG=/root/debian-13-generic-amd64.qcow2
STORAGE=local-lvm
BRIDGE=vmbr1
GW=10.10.10.1

#        id   name     ip           RAM(MB)  disk
NODES=( "101 k3s-cp 10.10.10.11 1536 20G"
        "102 k3s-w1 10.10.10.12 1152 30G"
        "103 k3s-w2 10.10.10.13 1152 30G"
        "104 k3s-w3 10.10.10.14 1152 30G" )

echo "==> 1/4 Host SSH key (to log into the nodes)"
[ -f /root/.ssh/id_ed25519 ] || ssh-keygen -q -t ed25519 -N "" -f /root/.ssh/id_ed25519
touch /root/kubelab-keys.pub
grep -qf /root/.ssh/id_ed25519.pub /root/kubelab-keys.pub || cat /root/.ssh/id_ed25519.pub >> /root/kubelab-keys.pub

echo "==> 2/4 Cloud-init snippet (base packages, zram, time zone)"
mkdir -p /var/lib/vz/snippets
cat > /var/lib/vz/snippets/kubelab-vendor.yaml <<'EOF'
#cloud-config
timezone: America/Guatemala
package_update: true
packages:
  - qemu-guest-agent
  - nfs-common
  - curl
  - zram-tools
write_files:
  - path: /etc/default/zramswap
    content: |
      ALGO=zstd
      PERCENT=60
      PRIORITY=100
runcmd:
  - systemctl enable --now qemu-guest-agent
  - systemctl restart zramswap
EOF

echo "==> 3/4 Debian 13 template (VM ${TPL_ID})"
if ! qm status $TPL_ID >/dev/null 2>&1; then
  [ -f "$IMG" ] || wget -q --show-progress -O "$IMG" "$IMG_URL"
  qm create $TPL_ID --name debian13-tpl --ostype l26 --cpu host --cores 2 --memory 1024 \
    --net0 virtio,bridge=$BRIDGE --scsihw virtio-scsi-single --agent enabled=1 \
    --serial0 socket --vga serial0
  qm set $TPL_ID --scsi0 ${STORAGE}:0,import-from=${IMG},discard=on
  qm set $TPL_ID --ide2 ${STORAGE}:cloudinit --boot order=scsi0
  qm set $TPL_ID --ciuser kube --sshkeys /root/kubelab-keys.pub \
    --nameserver 1.1.1.1 --searchdomain grupo1.lab \
    --cicustom vendor=local:snippets/kubelab-vendor.yaml --ciupgrade 0
  qm template $TPL_ID
fi

echo "==> 4/4 Clone the 4 VMs"
ORDER=1
for n in "${NODES[@]}"; do
  read -r ID NAME IP MEM DISK <<<"$n"
  if qm status $ID >/dev/null 2>&1; then echo "   $NAME already exists, skipping"; continue; fi
  qm clone $TPL_ID $ID --name $NAME
  qm set $ID --memory $MEM --balloon $MEM --ipconfig0 ip=${IP}/24,gw=${GW} --onboot 1 --startup order=${ORDER}
  qm resize $ID scsi0 $DISK
  qm start $ID
  echo "   $NAME -> $IP ($MEM MB, $DISK)"
  ORDER=$((ORDER+1))
  sleep 20
done

echo
echo "==> Waiting for the nodes to answer over SSH (2-4 min on HDD)..."
for n in "${NODES[@]}"; do
  read -r ID NAME IP MEM DISK <<<"$n"
  for i in $(seq 1 40); do
    if ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=3 kube@$IP true 2>/dev/null; then
      echo "   OK  $NAME ($IP)"; break
    fi
    sleep 6
  done
done
free -m
