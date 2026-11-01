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

Detailed diagrams (layout, request path, GitOps delivery and observability): [docs/architecture.md](docs/architecture.md).

## Node inventory

| Node | Role | IP | vCPU | RAM | Disk |
|---|---|---|---|---|---|
| pve | Proxmox hypervisor | 192.168.137.10 / 10.10.10.1 | 4 | 6 GB | 1 TB HDD |
| k3s-cp | Control plane | 10.10.10.11 | 2 | 1408 MB | 20 GB |
| k3s-w1 | Worker | 10.10.10.12 | 2 | 1408 MB | 30 GB |
| k3s-w2 | Worker | 10.10.10.13 | 2 | 1408 MB | 30 GB |
| k3s-w3 | Worker | 10.10.10.14 | 2 | 1408 MB | 30 GB |

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
tests/load/          k6 load test for the autoscaling demo
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

The repository is private: the instructor is added as a collaborator.

The cluster network `10.10.10.0/24` is reachable only through Tailscale. The Proxmox host `pve-grupo1` is a subnet router for it.

1. **Join the tailnet.** Accept the Tailscale invitation sent by the group, install Tailscale and sign in. On Linux, also run `sudo tailscale up --accept-routes` (Windows and macOS accept routes by default).
2. **Add the host names.** Append [`docs/hosts.txt`](docs/hosts.txt) to the hosts file:
   - Windows (Notepad as administrator): `C:\Windows\System32\drivers\etc\hosts`
   - Linux / macOS: `sudo tee -a /etc/hosts < docs/hosts.txt`
3. **Check the connection.** `ping 10.10.10.200` should answer, and http://app.grupo1.lab should open.

### Read-only accounts

| Service | User | Permissions |
|---|---|---|
| Argo CD | `docente` | `role:readonly`: views Applications, cannot sync, edit or delete |
| Grafana | `docente` | Viewer: dashboards and Explore, cannot edit |
| PostgreSQL (`db.grupo1.lab:5432`) | `docente` | `SELECT` only |

The passwords are stored in Doppler and are delivered to the instructor privately. They are never committed to this repository.

## Rebuilding the environment from scratch

1. [Proxmox and VMs](docs/01-proxmox.md)
2. [Kubernetes (k3s)](docs/02-k3s.md)
3. [Argo CD and platform services](docs/03-argocd-platform.md)
4. [Applications, secrets and CI/CD](docs/04-applications.md)
5. [Observability, autoscaling and load test](docs/05-observability.md)

## Verifying the platform

[`scripts/proxmox/verify-platform.sh`](scripts/proxmox/verify-platform.sh) checks every requirement against the running cluster (nodes, Argo CD, domains, HPA, PVCs, Prometheus targets, Loki, Doppler secrets) and prints PASS/FAIL per item. `--destructive` also deletes the web IngressRoute and `postgres-0` to prove self-healing and persistence.

```bash
cd /root/kubelab-grupo1 && git pull
bash scripts/proxmox/verify-platform.sh                 # read-only
bash scripts/proxmox/verify-platform.sh --destructive   # also self-healing and persistence
```
