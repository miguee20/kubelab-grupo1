# 01 · Proxmox VE installation and VM creation

## Hardware

| Component | Value |
|---|---|
| Machine | Dell Vostro desktop |
| CPU | Intel Core i5-3470S, 4 cores, VT-x enabled |
| RAM | 6 GB DDR3 |
| Disk | 1 TB HDD |
| Network | 1 Ethernet NIC (`nic0`), 1 Wi-Fi card (`wlp3s0`, unused) |

## Network topology

```
 Internet ── laptop Wi-Fi (Windows 11 Internet Connection Sharing)
                 │ Ethernet cable · 192.168.137.0/24 (same at home and at university)
         vmbr0 ─ pve 192.168.137.10 ── Tailscale (subnet router for 10.10.10.0/24)
                 │ NAT (iptables MASQUERADE)
         vmbr1 ─ 10.10.10.0/24  fixed internal network, no physical port
                 ├─ 10.10.10.1        pve host (gateway + NFS)
                 ├─ 10.10.10.11       k3s-cp
                 ├─ 10.10.10.12-14    k3s-w1..w3
                 └─ 10.10.10.200-210  MetalLB pool (Traefik = .200)
```

Since the cluster lives on `vmbr1`, no internal IP changes when the laptop's internet connection changes.

## 1. Installing Proxmox VE 9.2

1. Proxmox VE 9.2 ISO written to a USB drive with Rufus in **DD mode**.
2. Laptop connected to the Dell by cable, sharing its Wi-Fi to the Ethernet adapter (Internet Connection Sharing).
3. Graphical installer options:
   - Disk: 1 TB HDD, **ext4** (not ZFS, to avoid spending RAM on the ARC cache)
   - Time zone: America/Guatemala
   - Hostname: `pve.grupo1.lab`
   - IP `192.168.137.10/24`, gateway `192.168.137.1`, DNS `1.1.1.1`
4. Web UI at `https://192.168.137.10:8006` (user `root`, realm Linux PAM).

## 2. Host preparation

In the `pve` shell:

```bash
curl -fsSL https://raw.githubusercontent.com/miguee20/kubelab-grupo1/main/scripts/proxmox/01-host-setup.sh -o 01.sh && bash 01.sh
```

[`01-host-setup.sh`](../scripts/proxmox/01-host-setup.sh) does the following:
- Configures the no-subscription repositories.
- Creates `vmbr1` with NAT.
- Tunes memory: KSM, swappiness 10, HA services disabled.
- Exports `/srv/nfs/k8s` over NFS.
- Installs Tailscale advertising the route `10.10.10.0/24`.

## 3. Cloud-init template and VMs

```bash
curl -fsSL https://raw.githubusercontent.com/miguee20/kubelab-grupo1/main/scripts/proxmox/02-create-vms.sh -o 02.sh && bash 02.sh
```

[`02-create-vms.sh`](../scripts/proxmox/02-create-vms.sh) follows these steps:
1. Downloads the official `debian-13-generic-amd64.qcow2` image.
2. Builds template `9000` with:
   - `host` CPU type, virtio-scsi disk with discard
   - QEMU guest agent, serial console
   - Cloud-init with user `kube` and the host's SSH key
   - Vendor snippet `kubelab-vendor.yaml`: qemu-guest-agent, nfs-common, zram and time zone
3. Clones the 4 VMs and sets their static IP, memory, disk size and boot order.

| VMID | Node | IP | vCPU | RAM | Disk |
|---|---|---|---|---|---|
| 101 | k3s-cp | 10.10.10.11 | 2 | 1536 MB | 20 GB |
| 102 | k3s-w1 | 10.10.10.12 | 2 | 1152 MB | 30 GB |
| 103 | k3s-w2 | 10.10.10.13 | 2 | 1152 MB | 30 GB |
| 104 | k3s-w3 | 10.10.10.14 | 2 | 1152 MB | 30 GB |

![Proxmox with the 4 cluster VMs running](evidence/01-proxmox-vms.png)

## 4. Host memory tuning

```bash
curl -fsSL https://raw.githubusercontent.com/miguee20/kubelab-grupo1/main/scripts/proxmox/04-memory-tuning.sh -o 04.sh && bash 04.sh
```

[`04-memory-tuning.sh`](../scripts/proxmox/04-memory-tuning.sh) applies the following:
- Adds zram swap on the host (compressed in RAM, used before the HDD swap).
- Enables the virtio-balloon device on every VM. With free page reporting, memory the guests free is returned to the host.
- Raises the control plane to 1536 MB. With 1024 MB the k3s server swapped heavily during the first Argo CD sync (I/O pressure above 90 %) and the API server restarted.
- Disables unused k3s server controllers (cloud controller, Helm controller, network policy) and sets `GOGC=50`.

### Memory budget (6 GB)

| Consumer | RAM |
|---|---|
| Proxmox host (pveproxy, pvedaemon, NFS, Tailscale) | ~1.3 GB |
| VMs (fixed size) | 4.9 GB |
| KSM savings (identical pages across the 4 Debian VMs) | ~0.3–0.6 GB |
| zram on the host and inside each VM | compressed swap in RAM, before the HDD |
