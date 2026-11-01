# Architecture

## Physical and virtual layout

```mermaid
flowchart TB
  internet((Internet))
  subgraph laptop["Laptop · Windows 11"]
    wifi[Wi-Fi]
    ics["Ethernet · ICS<br/>192.168.137.1"]
  end
  subgraph dell["Dell Vostro · i5-3470S · 6 GB · 1 TB HDD"]
    subgraph pve["Proxmox VE 9.2 (pve)"]
      vmbr0["vmbr0 · 192.168.137.10"]
      ts["Tailscale<br/>subnet router 10.10.10.0/24"]
      nat["NAT (MASQUERADE)"]
      nfs[("NFS export<br/>/srv/nfs/k8s")]
      subgraph vmbr1["vmbr1 · 10.10.10.0/24 (internal)"]
        cp["k3s-cp · 10.10.10.11<br/>control plane, NoSchedule"]
        w1["k3s-w1 · 10.10.10.12"]
        w2["k3s-w2 · 10.10.10.13"]
        w3["k3s-w3 · 10.10.10.14"]
        lb{{"MetalLB pool .200-.210<br/>Traefik 10.10.10.200"}}
      end
    end
  end
  instructor["Instructor laptop<br/>Tailscale + docs/hosts.txt"]

  internet --- wifi --> ics --> vmbr0
  vmbr0 --- nat --- vmbr1
  vmbr0 --- ts
  instructor -. tailnet .-> ts -.-> lb
  w1 & w2 & w3 -- PVCs --> nfs
```

The cluster network (`vmbr1`) never changes. Only the laptop's Wi-Fi does, so the cluster works the same at home, at the university and on a phone hotspot.

## Request path

```mermaid
flowchart LR
  user["Browser / SQL client"] -->|"*.grupo1.lab → 10.10.10.200"| traefik["Traefik<br/>2 replicas · LoadBalancer"]
  traefik -->|"IngressRoute app"| web["web · nginx<br/>HPA 2-6"]
  traefik -->|"IngressRoute api"| api["api · Node.js<br/>HPA 2-6"]
  traefik -->|"IngressRouteTCP :5432"| pg[("PostgreSQL 17<br/>StatefulSet + PVC")]
  traefik -->|"IngressRoute grafana"| grafana[Grafana]
  traefik -->|"IngressRoute prometheus"| prom[Prometheus]
  traefik -->|"IngressRoute argocd"| argo[Argo CD]
  web -->|"/api/* proxy"| api
  api --> pg
```

## Delivery path (GitOps)

```mermaid
flowchart LR
  dev["Merge to main<br/>apps/api or apps/web"] --> gha["GitHub Actions<br/>(path filter per app)"]
  doppler[("Doppler<br/>kubelab / prd")] -->|GH_PAT| gha
  gha -->|"test, build, push :sha7"| ghcr[(GHCR)]
  gha -->|"commit new tag to k8s/apps"| repo[(GitHub repo)]
  repo -->|"poll / refresh"| argocd["Argo CD<br/>app of apps · prune · selfHeal"]
  argocd -->|"RollingUpdate"| cluster[k3s cluster]
  ghcr -->|"image pull"| cluster
  doppler -->|"Doppler Operator<br/>DopplerSecret"| cluster
```

## Observability path

```mermaid
flowchart LR
  ne["node-exporter (4 nodes)"] --> prom[Prometheus]
  ksm[kube-state-metrics] --> prom
  cad["kubelet cAdvisor"] --> prom
  apim["api /metrics"] --> prom
  pt["Promtail DaemonSet (4 nodes)"] --> loki[Loki]
  prom --> grafana["Grafana<br/>datasources + dashboard from code"]
  loki --> grafana
```
