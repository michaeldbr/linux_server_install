# Kubernetes-laag

Deze laag bereidt een node voor op Kubernetes.

1. Containerd installeren + `SystemdCgroup=true`
2. Kernel modules + sysctl voor Kubernetes networking
3. Swap uitschakelen (+ uit `/etc/fstab`)
4. Kubernetes repo + kubeadm/kubelet/kubectl
5. Kubelet runtime endpoint op containerd socket
6. Optioneel `crictl`
7. CNI helper (`70_cni.sh`) voor Flannel/Calico
8. `95_verify_repair.sh` voor check + repair van Kubernetes-laag

## CNI helper

`70_cni.sh` probeert een CNI toe te passen zodra de API bereikbaar is en
`/etc/kubernetes/admin.conf` bestaat.

Default:

- `CNI_PLUGIN=flannel`

Alternatief:

- `CNI_PLUGIN=calico`

Voorbeeld:

```bash
sudo CNI_PLUGIN=flannel bash scripts/kubernetes/70_cni.sh
```
