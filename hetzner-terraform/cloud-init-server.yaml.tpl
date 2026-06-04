#cloud-config
package_update: true
package_upgrade: true
packages:
  - curl
  - wget
  - git
  - unzip
  - jq
  - open-iscsi
  - nfs-common

write_files:
  - path: /etc/sysctl.d/99-k3s.conf
    content: |
      net.ipv4.ip_forward = 1
      net.bridge.bridge-nf-call-iptables = 1
      net.bridge.bridge-nf-call-ip6tables = 1
  - path: /usr/local/bin/setup-kubeconfig.sh
    permissions: "0755"
    content: |
      #!/bin/bash
      set -euo pipefail
      until kubectl get nodes 2>/dev/null; do sleep 3; done
      PUBLIC_IP=$(curl -s http://169.254.169.254/hetzner/v1/metadata/public-ipv4)
      mkdir -p /root/.kube
      cp /etc/rancher/k3s/k3s.yaml /root/.kube/config
      sed -i "s/127.0.0.1/$PUBLIC_IP/g" /root/.kube/config
      chmod 600 /root/.kube/config
  - path: /usr/local/bin/install-k3s.sh
    permissions: "0755"
    content: |
      #!/bin/bash
      set -euo pipefail

      export K3S_TOKEN="${k3s_token}"
      export K3S_NODE_NAME="${cluster_name}-$(hostname -s)"

      %{ if k3s_version != "" ~}
      export INSTALL_K3S_VERSION="${k3s_version}"
      %{ endif ~}

      %{ if role == "server" ~}
      curl -sfL https://get.k3s.io | sh -s - server \
        --cluster-init \
        --disable=traefik \
        --node-ip="${node_ip}" \
        --advertise-address="${node_ip}"
      %{ else ~}
      until curl -sk "https://${control_plane_ip}:6443/ping" >/dev/null 2>&1; do
        echo "Waiting for control plane at ${control_plane_ip}..."
        sleep 5
      done
      curl -sfL https://get.k3s.io | sh -s - agent \
        --server "https://${control_plane_ip}:6443" \
        --node-ip="${node_ip}"
      %{ endif ~}

runcmd:
  - sysctl --system
  - systemctl enable --now open-iscsi
  - /usr/local/bin/install-k3s.sh
  %{ if role == "server" ~}
  - /usr/local/bin/setup-kubeconfig.sh
  %{ endif ~}
