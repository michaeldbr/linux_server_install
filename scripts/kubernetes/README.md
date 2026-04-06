# Kubernetes-laag

Deze laag bereidt een node voor op Kubernetes (zonder cluster init/join te starten):

1. Containerd installeren + `SystemdCgroup=true`
2. Kernel modules + sysctl voor Kubernetes networking
3. Swap uitschakelen (+ uit `/etc/fstab`)
4. Kubernetes repo + kubeadm/kubelet/kubectl
5. Kubelet runtime endpoint op containerd socket
6. Optioneel `crictl`

7. `10_verify_and_repair.sh` voor check + repair van Kubernetes-laag
