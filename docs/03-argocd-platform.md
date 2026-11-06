# 03 · Argo CD and platform services

## GitOps model

```
k8s/argocd/root.yaml              (applied once at bootstrap)
   └── k8s/argocd/apps/           (one Application per component)
         ├── argocd               → k8s/argocd/install (Argo CD manages itself)
         ├── metallb              → Helm chart metallb
         ├── metallb-config       → k8s/platform/metallb (IPAddressPool + L2Advertisement)
         ├── traefik              → Helm chart traefik (LoadBalancer 10.10.10.200)
         ├── platform-routes      → k8s/platform/routes (IngressRoutes for platform tools)
         ├── nfs-provisioner      → Helm chart nfs-subdir-external-provisioner (default StorageClass)
         └── metrics-server       → Helm chart metrics-server
```

Every Application has `automated` sync with `prune: true` and `selfHeal: true` (CD-04). Any manual change in the cluster is reverted to what is in Git. Applications that depend on CRDs from another chart use `SkipDryRunOnMissingResource` and a retry policy, so they converge on their own once the CRDs exist.

## Bootstrap (the only manual `kubectl apply`)

In the `pve` shell:

```bash
bash /root/kubelab-grupo1/scripts/proxmox/05-bootstrap-argocd.sh
```

[`05-bootstrap-argocd.sh`](../scripts/proxmox/05-bootstrap-argocd.sh) installs Argo CD from [`k8s/argocd/install`](../k8s/argocd/install/kustomization.yaml) and creates the root Application. After that, nothing is applied by hand.

So that Argo CD can also read the repository while it is private, the script first creates, from Doppler, the two Secrets that must exist before Argo CD can read it: the Doppler service token (`doppler-token-secret`) and the repository credentials (`argocd/argocd-repo`, labelled `argocd.argoproj.io/secret-type: repository`). Once the Doppler operator runs, the DopplerSecret `argocd-repo` keeps those credentials in sync with `GH_PAT`.

## Argo CD accounts (ACC-03)

| Account | Role | Password (Doppler) |
|---|---|---|
| `admin` | Full access | `ARGOCD_ADMIN_PASSWORD` |
| `docente` | `role:readonly`: sees every Application, cannot sync, edit or delete | `ARGOCD_VIEWER_PASSWORD` |

The account and its RBAC rule are declared in [`k8s/argocd/install`](../k8s/argocd/install/kustomization.yaml) (`argocd-cm` and `argocd-rbac-cm`). Argo CD stores only bcrypt hashes in `argocd-secret`, so the passwords are applied with one script. Doppler syncs both values into `argocd/argocd-users`, and [`06-argocd-users.sh`](../scripts/proxmox/06-argocd-users.sh) hashes them and writes the hashes:

```bash
bash /root/kubelab-grupo1/scripts/proxmox/06-argocd-users.sh
```

The script also deletes `argocd-initial-admin-secret`, so the random first password stops existing.

![docente sees every Application, but Sync is rejected with "permission denied"](evidence/03-argocd-readonly-docente.png)

## Pinned versions

Every Helm chart and the Argo CD manifest use an exact version, so the cluster renders the same objects on every rebuild. A new upstream release never reaches the cluster unless a commit changes the version.

| Component | Version |
|---|---|
| k3s | v1.36.5+k3s1 |
| Argo CD (`install.yaml`) | v3.5.6 |
| MetalLB | 0.16.1 |
| Traefik | 42.2.0 |
| nfs-subdir-external-provisioner | 4.0.18 |
| metrics-server | 3.14.0 |
| Doppler Kubernetes Operator | 1.7.5 |
| Prometheus | 29.40.3 |
| Loki | 7.5.0 |
| Promtail | 6.17.1 |
| Grafana | 10.5.15 |

## Argo CD trimmed for 6 GB

| Change | Saving |
|---|---|
| Dex (SSO), notifications and ApplicationSet controllers removed | ~200 MB |
| Memory requests/limits on controller, repo-server, server and redis | Predictable usage |
| `server.insecure: true` | TLS is not needed inside the lab; Traefik serves HTTP |

## Network services

| Component | Configuration |
|---|---|
| MetalLB | Layer 2 mode, pool `10.10.10.200-10.10.10.210` on the internal bridge `vmbr1` (NET-01, INF-06) |
| Traefik | 2 replicas, PodDisruptionBudget, `LoadBalancer` Service pinned to `10.10.10.200` (NET-02). Entry points: `web` (80) and `postgres` (5432) |
| IngressRoute | `argocd.grupo1.lab` → `argocd-server:80` (CD-02) |

## Storage

`nfs-subdir-external-provisioner` creates one folder per PVC in `/srv/nfs/k8s` on the Proxmox host (exported only to `10.10.10.0/24`). The `nfs` StorageClass is the cluster default (PER-01). Since the data lives outside the worker VMs, a pod can be deleted or rescheduled to any worker and still find its volume (PER-02).

The export uses `async`. With `sync`, every `fsync` from SQLite (Grafana), PostgreSQL, Prometheus and Loki waited for the single HDD. Grafana's first start (about 200 migrations) then took longer than its liveness probe and the worker stalled on I/O. The trade-off is that a power loss on the host could drop the last few seconds of writes, which is acceptable for a lab.

## Verification

```bash
kubectl -n argocd get applications          # all Synced / Healthy
kubectl -n traefik get svc traefik          # EXTERNAL-IP 10.10.10.200
kubectl get storageclass                    # nfs (default)
kubectl top nodes                           # metrics-server working
```

![Argo CD with every platform Application Synced and Healthy](evidence/03-argocd-platform-apps.png)

![Tailscale subnet route 10.10.10.0/24 approved for pve-grupo1, key expiry disabled](evidence/03-tailscale-subnet-route.png)
