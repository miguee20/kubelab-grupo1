#!/usr/bin/env bash
# KubeLab - Paso 3: instalar k3s en los 4 nodos (se ejecuta en la shell de pve como root)
# - k3s-cp: servidor (control plane) con taint NoSchedule -> no corre cargas de aplicaciones
# - k3s-w1..w3: agentes
# - Se desactivan los add-ons empaquetados (Traefik, ServiceLB, local-storage, metrics-server)
#   porque MetalLB, Traefik, NFS y metrics-server se instalan con Argo CD desde el repositorio.
set -euo pipefail

CP=10.10.10.11
WORKERS=(10.10.10.12 10.10.10.13 10.10.10.14)
SSH="ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5"
CHANNEL=stable

echo "==> 1/4 Servidor k3s en k3s-cp ($CP)"
$SSH kube@$CP "curl -sfL https://get.k3s.io | sudo INSTALL_K3S_CHANNEL=$CHANNEL sh -s - server \
  --node-ip $CP --tls-san $CP --tls-san k3s-cp.grupo1.lab \
  --write-kubeconfig-mode 644 \
  --disable traefik --disable servicelb --disable local-storage --disable metrics-server \
  --node-taint node-role.kubernetes.io/control-plane=true:NoSchedule \
  --kubelet-arg=system-reserved=memory=96Mi --kubelet-arg='eviction-hard=memory.available<64Mi'"

TOKEN=$($SSH kube@$CP "sudo cat /var/lib/rancher/k3s/server/node-token")

echo "==> 2/4 Agentes k3s en los workers"
for IP in "${WORKERS[@]}"; do
  echo "   -> $IP"
  $SSH kube@$IP "curl -sfL https://get.k3s.io | sudo INSTALL_K3S_CHANNEL=$CHANNEL \
    K3S_URL=https://$CP:6443 K3S_TOKEN=$TOKEN sh -s - agent \
    --node-ip $IP --node-label node-role.kubernetes.io/worker=true \
    --kubelet-arg=system-reserved=memory=96Mi --kubelet-arg='eviction-hard=memory.available<64Mi'"
done

echo "==> 3/4 kubectl en el host pve"
if ! command -v kubectl >/dev/null; then
  KVER=$($SSH kube@$CP "k3s --version | head -1 | awk '{print \$3}' | cut -d+ -f1")
  curl -fsSL -o /usr/local/bin/kubectl "https://dl.k8s.io/release/${KVER}/bin/linux/amd64/kubectl"
  chmod +x /usr/local/bin/kubectl
fi
mkdir -p /root/.kube
$SSH kube@$CP "cat /etc/rancher/k3s/k3s.yaml" | sed "s/127.0.0.1/$CP/" > /root/.kube/config
chmod 600 /root/.kube/config
grep -q 'source <(kubectl completion bash)' /root/.bashrc || echo 'source <(kubectl completion bash); alias k=kubectl; complete -F __start_kubectl k' >> /root/.bashrc

echo "==> 4/4 Esperando nodos Ready..."
for i in $(seq 1 30); do
  READY=$(kubectl get nodes --no-headers 2>/dev/null | awk '$2=="Ready"' | wc -l)
  [ "$READY" -eq 4 ] && break
  sleep 5
done
kubectl get nodes -o wide
echo
kubectl describe node k3s-cp | grep -A1 Taints
echo
free -m
