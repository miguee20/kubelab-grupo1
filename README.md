# KubeLab · Grupo 1

Plataforma Kubernetes sobre Proxmox con GitOps: clúster k3s de 4 nodos virtualizado en Proxmox VE, aplicaciones desplegadas con Argo CD, observabilidad con Prometheus/Loki/Grafana y secretos gestionados con Doppler.

Dominio funcional: **inventario de una tienda de abarrotes** (entidad `productos`).

## Integrantes

| Integrante | GitHub | Área principal |
|---|---|---|
| Miguel | @miguee20 | Proxmox, red, k3s, Tailscale, Argo CD |
| Javier Sánchez | @JavierSanchez22 | API (Node.js), base de datos, migraciones |
| Chrivill02 | @Chrivill02 | Aplicación web, GitHub Actions, Doppler |
| Emilio Medina | @emilioxmedina | Observabilidad, HPA, prueba de carga |

## Arquitectura

> Pendiente: diagrama en `docs/arquitectura.png`.

- Host físico: Dell Vostro (i5-3470S, 6 GB RAM, HDD 1 TB) con Proxmox VE.
- Red interna fija `10.10.10.0/24` (bridge `vmbr1`), con NAT hacia el uplink: cable Ethernet a la laptop, que comparte su WiFi (igual en casa y en la universidad).
- Acceso externo mediante Tailscale (subnet router en el host Proxmox).

## Inventario de nodos

| Nodo | Rol | IP | vCPU | RAM | Disco |
|---|---|---|---|---|---|
| pve | Hipervisor Proxmox | 192.168.137.10 / 10.10.10.1 | 4 | 6 GB | 1 TB HDD |
| k3s-cp | Control plane | 10.10.10.11 | 2 | 1024 MB | 20 GB |
| k3s-w1 | Worker | 10.10.10.12 | 2 | 1152 MB | 30 GB |
| k3s-w2 | Worker | 10.10.10.13 | 2 | 1152 MB | 30 GB |
| k3s-w3 | Worker | 10.10.10.14 | 2 | 1152 MB | 30 GB |

Pool de MetalLB: `10.10.10.200-10.10.10.210`. Traefik: `10.10.10.200`.

## Estructura del repositorio

```
apps/api/            Código y Dockerfile de la API (Node.js)
apps/web/            Código y Dockerfile de la aplicación web
k8s/apps/            Manifiestos de api, web y base de datos
k8s/platform/        MetalLB, Traefik, StorageClass, Doppler
k8s/observability/   Prometheus, Grafana, Loki, Promtail
k8s/argocd/          Applications de Argo CD (app of apps)
.github/workflows/   Pipelines de CI/CD
docs/                VMs, instalación, diagramas, hosts.txt, evidencias
scripts/             Utilidades del equipo
```

## URLs del servicio

| URL | Servicio | Qué se debe ver |
|---|---|---|
| http://app.grupo1.lab | Aplicación web | Inventario de productos con CRUD |
| http://api.grupo1.lab/health | API | `{"status":"ok"}` |
| http://api.grupo1.lab/metrics | API | Métricas en formato Prometheus |
| db.grupo1.lab:5432 | PostgreSQL | Conexión con cliente SQL |
| http://grafana.grupo1.lab | Grafana | Dashboard KubeLab |
| http://prometheus.grupo1.lab | Prometheus | Targets en estado UP |
| http://argocd.grupo1.lab | Argo CD | Applications Synced/Healthy |

## Acceso del docente

> Pendiente: unirse a Tailscale y copiar `docs/hosts.txt`.

## Reconstruir el entorno desde cero

1. [Proxmox y VMs](docs/01-proxmox.md)
2. [Kubernetes (k3s)](docs/02-k3s.md)
