# Uso:  .\scripts\commit-as.ps1 javier "feat(api): add products CRUD"
# Hace commit de lo que esté en staging (git add) a nombre del integrante indicado.
# Acordado con el docente: los commits se registran a nombre de cada integrante.
param(
  [Parameter(Mandatory=$true)][ValidateSet("miguel","javier","chris","emilio")][string]$Quien,
  [Parameter(Mandatory=$true)][string]$Mensaje
)

$autores = @{
  miguel = "miguee20 <124699281+miguee20@users.noreply.github.com>"
  javier = "JavierSanchez22 <197183514+JavierSanchez22@users.noreply.github.com>"
  chris  = "Chrivill02 <99997132+Chrivill02@users.noreply.github.com>"
  emilio = "emilioxmedina <61241178+emilioxmedina@users.noreply.github.com>"
}

if ($Mensaje -notmatch '^(feat|fix|chore|docs|ci|refactor|test|perf|style|build)(\(.+\))?: .+') {
  Write-Error "El mensaje no cumple Conventional Commits. Ej: feat(api): add /health endpoint"
  exit 1
}

git commit --author="$($autores[$Quien])" -m "$Mensaje"
