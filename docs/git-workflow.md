# Git workflow

1. `main` is protected: no force pushes and no direct pushes; every change goes through a pull request.
2. Each task lives on its own branch: `feat/api-crud`, `ci/api-workflow`, `docs/proxmox-vms`, etc.
3. Commit messages follow Conventional Commits: `type(scope): description` (`feat`, `fix`, `chore`, `docs`, `ci`).
4. Pull requests are merged into `main`; Argo CD syncs the cluster from `main`.
