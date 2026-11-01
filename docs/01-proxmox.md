# 01 · Instalación de Proxmox VE y creación de las VMs

## Hardware

| Componente | Valor |
|---|---|
| Equipo | Dell Vostro (escritorio) |
| CPU | Intel Core i5-3470S, 4 núcleos, VT-x habilitado |
| RAM | 6 GB DDR3 |
| Disco | HDD 1 TB |
| Red | 1 NIC Ethernet (`nic0`), 1 WiFi (`wlp3s0`, sin usar) |

## Topología de red

```
 Internet ── WiFi laptop (Windows 11, Conexión compartida a Internet)
                 │ cable Ethernet · 192.168.137.0/24 (siempre igual: casa y universidad)
         vmbr0 ─ pve 192.168.137.10 ── Tailscale (subnet router 10.10.10.0/24)
                 │ NAT (iptables MASQUERADE)
         vmbr1 ─ 10.10.10.0/24  red interna fija, sin puerto físico
                 ├─ 10.10.10.1        host pve (gateway + NFS)
                 ├─ 10.10.10.11       k3s-cp
                 ├─ 10.10.10.12-14    k3s-w1..w3
                 └─ 10.10.10.200-210  pool MetalLB (Traefik = .200)
```

Como el clúster vive en `vmbr1`, ninguna IP interna cambia aunque cambie la red por la que la laptop sale a internet.

## 1. Instalación de Proxmox VE 9.2

1. ISO de Proxmox VE 9.2 grabada en USB con Rufus en **modo DD**.
2. Laptop conectada a la Dell por cable, con *Conexión compartida a Internet* del WiFi hacia Ethernet.
3. Instalador gráfico con estas opciones:
   - Disco: HDD 1 TB, **ext4** (no ZFS, para no consumir RAM en caché ARC)
   - Zona horaria: America/Guatemala
   - Hostname: `pve.grupo1.lab`
   - IP: `192.168.137.10/24`, gateway `192.168.137.1`, DNS `1.1.1.1`
4. Acceso web en `https://192.168.137.10:8006` (usuario `root`, realm Linux PAM).

## 2. Preparación del host

En la shell de `pve`:

```bash
curl -fsSL https://raw.githubusercontent.com/miguee20/kubelab-grupo1/main/scripts/proxmox/01-host-setup.sh -o 01.sh && bash 01.sh
```

El script [`01-host-setup.sh`](../scripts/proxmox/01-host-setup.sh) hace lo siguiente:
- Configura los repositorios sin suscripción.
- Crea `vmbr1` con NAT.
- Ajusta memoria: KSM, swappiness 10 y servicios HA apagados.
- Instala el servidor NFS en `/srv/nfs/k8s`.
- Instala Tailscale anunciando la ruta `10.10.10.0/24`.

## 3. Plantilla cloud-init y VMs

```bash
curl -fsSL https://raw.githubusercontent.com/miguee20/kubelab-grupo1/main/scripts/proxmox/02-create-vms.sh -o 02.sh && bash 02.sh
```

El script [`02-create-vms.sh`](../scripts/proxmox/02-create-vms.sh) sigue estos pasos:
1. Descarga la imagen oficial `debian-13-generic-amd64.qcow2`.
2. Crea la plantilla `9000` con estas características:
   - CPU `host`, disco virtio-scsi con discard
   - Agente QEMU, consola serial
   - Cloud-init con usuario `kube` y llave SSH del host
   - Snippet `kubelab-vendor.yaml`: qemu-guest-agent, nfs-common, zram y zona horaria
3. Clona las 4 VMs y les asigna IP fija, memoria, tamaño de disco y orden de arranque.

| VMID | Nodo | IP | vCPU | RAM | Disco |
|---|---|---|---|---|---|
| 101 | k3s-cp | 10.10.10.11 | 2 | 1024 MB | 20 GB |
| 102 | k3s-w1 | 10.10.10.12 | 2 | 1152 MB | 30 GB |
| 103 | k3s-w2 | 10.10.10.13 | 2 | 1152 MB | 30 GB |
| 104 | k3s-w3 | 10.10.10.14 | 2 | 1152 MB | 30 GB |

### Presupuesto de memoria (6 GB)

| Consumidor | RAM |
|---|---|
| Host Proxmox (pveproxy, pvedaemon, NFS, Tailscale) | ~1.3 GB |
| VMs (fijo, sin ballooning) | 4.4 GB |
| Ahorro por KSM (páginas idénticas entre las 4 VMs Debian) | ~0.3–0.6 GB |
| zram dentro de cada VM (swap comprimido en RAM) | +60 % efectivo |
