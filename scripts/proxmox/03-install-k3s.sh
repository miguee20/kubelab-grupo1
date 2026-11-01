#!/usr/bin/env bash
# KubeLab - Step 3: install k3s on the 4 nodes (run in the pve shell as root)
# - k3s-cp: server (control plane) with a NoSchedule taint -> no application workloads
# - k3s-w1..w3: agents
# - Bundled add-ons are disabled (Traefik, ServiceLB, local-storage, metrics-server)
#   because MetalLB, Traefik, NFS and metrics-server are installed by Argo CD from the repository.
set -euo pipefail

CP=10.10.10.11
WORKERS=(10.10.10.12 10.10.10.13 10.10.10.14)
SSH="ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5"
CHANNEL=stable

echo "==> 1/4 k3s server on k3s-cp ($CP)"
$SSH kube@$CP "curl -sfL https://get.k3s.io | sudo INSTALL_K3S_CHANNEL=$CHANNEL sh -s - server \
  --node-ip $CP --tls-san $CP --tls-san k3s-cp.grupo1.lab \
  --write-kubeconfig-mode 644 \
  --disable traefik --disable servicelb --disable local-storage --disable metrics-server \
  --node-taint node-role.kubernetes.io/control-plane=true:NoSchedule \
  --disable-cloud-controller --disable-helm-controller --disable-network-policy \
  --kubelet-arg=system-reserved=memory=96Mi --kubelet-arg='eviction-hard=memory.available<64Mi'"
# Go garbage collector returns memory sooner (lower peak RAM on the 1.5 GB control plane)
$SSH kube@$CP "echo GOGC=50 | sudo tee -a /etc/systemd/system/k3s.service.env >/dev/null && sudo systemctl restart k3s"

TOKEN=$($SSH kube@$CP "sudo cat /var/lib/rancher/k3s/server/node-token")

echo "==> 2/4 k3s agents on the workers"
for IP in "${WORKERS[@]}"; do
  echo "   -> $IP"
  $SSH kube@$IP "curl -sfL https://get.k3s.io | sudo INSTALL_K3S_CHANNEL=$CHANNEL \
    K3S_URL=https://$CP:6443 K3S_TOKEN=$TOKEN sh -s - agent \
    --node-ip $IP \
    --kubelet-arg=system-reserved=memory=96Mi --kubelet-arg='eviction-hard=memory.available<64Mi'"
done

echo "==> 3/4 kubectl on the pve host"
if ! command -v kubectl >/dev/null; then
  KVER=$($SSH kube@$CP "k3s --version | head -1 | awk '{print \$3}' | cut -d+ -f1")
  curl -fsSL -o /usr/local/bin/kubectl "https://dl.k8s.io/release/${KVER}/bin/linux/amd64/kubectl"
  chmod +x /usr/local/bin/kubectl
fi
mkdir -p /root/.kube
$SSH kube@$CP "cat /etc/rancher/k3s/k3s.yaml" | sed "s/127.0.0.1/$CP/" > /root/.kube/config
chmod 600 /root/.kube/config
grep -q 'source <(kubectl completion bash)' /root/.bashrc || echo 'source <(kubectl completion bash); alias k=kubectl; complete -F __start_kubectl k' >> /root/.bashrc

echo "==> 4/4 Waiting for nodes to be Ready..."
for i in $(seq 1 30); do
  READY=$(kubectl get nodes --no-headers 2>/dev/null | awk '$2=="Ready"' | wc -l)
  [ "$READY" -eq 4 ] && break
  sleep 5
done
# The worker role is set through the API: the kubelet cannot self-assign node-role.* labels
for N in k3s-w1 k3s-w2 k3s-w3; do kubectl label node $N node-role.kubernetes.io/worker=true --overwrite >/dev/null; done
kubectl get nodes -o wide
echo
kubectl describe node k3s-cp | grep -A1 Taints
echo
free -m
