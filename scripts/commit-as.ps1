# Usage:  .\scripts\commit-as.ps1 javier "feat(api): add products CRUD"
# Commits the staged changes under the given team member's name.
param(
  [Parameter(Mandatory=$true)][ValidateSet("miguel","javier","chris","emilio")][string]$Member,
  [Parameter(Mandatory=$true)][string]$Message
)

$authors = @{
  miguel = "miguee20 <124699281+miguee20@users.noreply.github.com>"
  javier = "JavierSanchez22 <197183514+JavierSanchez22@users.noreply.github.com>"
  chris  = "Chrivill02 <99997132+Chrivill02@users.noreply.github.com>"
  emilio = "emilioxmedina <61241178+emilioxmedina@users.noreply.github.com>"
}

if ($Message -notmatch '^(feat|fix|chore|docs|ci|refactor|test|perf|style|build)(\(.+\))?: .+') {
  Write-Error "Message is not a Conventional Commit. Example: feat(api): add /health endpoint"
  exit 1
}

git commit --author="$($authors[$Member])" -m "$Message"
