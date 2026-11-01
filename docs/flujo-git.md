# Flujo de trabajo con Git

1. `main` está protegida: no se permite push forzado ni push directo; todo entra por Pull Request.
2. Cada tarea vive en una rama: `feat/api-crud`, `ci/workflow-api`, `docs/proxmox-vms`, etc.
3. Los mensajes siguen Conventional Commits: `feat`, `fix`, `chore`, `docs`, `ci`.
4. Los commits se registran a nombre del integrante responsable del área, con `scripts/commit-as.ps1`.
5. El PR se fusiona a `main`; Argo CD sincroniza el clúster a partir de `main`.
