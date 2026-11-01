# KubeLab · Group 1

Kubernetes platform on Proxmox with GitOps: a 4-node k3s cluster virtualized on Proxmox VE, applications deployed with Argo CD, observability with Prometheus/Loki/Grafana and secrets managed with Doppler.

Business domain: **grocery store inventory** (`products` entity).

## Architecture

```
 Internet ── laptop Wi-Fi (Windows 11 Internet Connection Sharing)
                 │ Ethernet cable · 192.168.137.0/24 (same at home and at university)
         vmbr0 ─ pve 192.168.137.10 ── Tailscale (subnet router for 10.10.10.0/24)
                 │ NAT
         vmbr1 ─ 10.10.10.0/24  fixed internal network, no physical port
                 ├─ 10.10.10.1        pve host (gateway + NFS)
                 ├─ 10.10.10.11       k3s-cp
                 ├─ 10.10.10.12-14    k3s-w1..w3
                 └─ 10.10.10.200-210  MetalLB pool (Traefik = .200)
```

- Physical host: Dell Vostro (i5-3470S, 6 GB RAM, 1 TB HDD) running Proxmox VE 9.2.
- The cluster lives on `vmbr1`, so no internal IP changes when the uplink network changes.
- External access through Tailscale (subnet router on the Proxmox host).

## Node inventory

| Node | Role | IP | vCPU | RAM | Disk |
|---|---|---|---|---|---|
| pve | Proxmox hypervisor | 192.168.137.10 / 10.10.10.1 | 4 | 6 GB | 1 TB HDD |
| k3s-cp | Control plane | 10.10.10.11 | 2 | 1536 MB | 20 GB |
| k3s-w1 | Worker | 10.10.10.12 | 2 | 1152 MB | 30 GB |
| k3s-w2 | Worker | 10.10.10.13 | 2 | 1152 MB | 30 GB |
| k3s-w3 | Worker | 10.10.10.14 | 2 | 1152 MB | 30 GB |

MetalLB pool: `10.10.10.200-10.10.10.210`. Traefik: `10.10.10.200`.

## Repository layout

```
apps/api/            API source code and Dockerfile (Node.js)
apps/web/            Web application source code and Dockerfile
k8s/apps/            Manifests for api, web and database
k8s/platform/        MetalLB, Traefik, StorageClass, Doppler
k8s/observability/   Prometheus, Grafana, Loki, Promtail
k8s/argocd/          Argo CD Applications (app of apps)
.github/workflows/   CI/CD pipelines
docs/                VM creation, cluster install, diagrams, hosts.txt, evidence
scripts/             Proxmox provisioning and team utilities
```

## Service URLs

| URL | Service | What you should see |
|---|---|---|
| http://app.grupo1.lab | Web application | Product inventory with create, edit and delete |
| http://api.grupo1.lab/health | API | `{"status":"ok"}` |
| http://api.grupo1.lab/metrics | API | Metrics in Prometheus format |
| db.grupo1.lab:5432 | PostgreSQL | Connection from an SQL client |
| http://grafana.grupo1.lab | Grafana | KubeLab dashboard |
| http://prometheus.grupo1.lab | Prometheus | Targets in UP state |
| http://argocd.grupo1.lab | Argo CD | Applications Synced / Healthy |

## Instructor access

> Pending: join Tailscale and copy `docs/hosts.txt`.

## Rebuilding the environment from scratch

1. [Proxmox and VMs](docs/01-proxmox.md)
2. [Kubernetes (k3s)](docs/02-k3s.md)
3. [Argo CD and platform services](docs/03-argocd-platform.md)
4. [Applications, secrets and CI/CD](docs/04-applications.md)
