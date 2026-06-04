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
  - path: /usr/local/bin/setup-private-net.sh
    permissions: "0755"
    content: |
      #!/bin/bash
      set -euo pipefail

      # Hetzner dokłada prywatną sieć jako drugi NIC, ale NIE konfiguruje go w OS.
      # Nazwa interfejsu zależy od typu serwera (enp7s0/ens10/...), więc wykrywamy
      # go w runtime: pomijamy loopback, interfejs z trasą domyślną (publiczny)
      # oraz wirtualne (docker/cni/...). Podnosimy przez DHCP, żeby Hetzner przydzielił
      # ${node_ip} ZANIM wystartuje k3s/etcd (inaczej etcd nie zbinduje się do tego IP).

      PRIMARY_IF=$(ip -o route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')

      PRIV_IF=""
      for IF in $(ls /sys/class/net); do
        case "$IF" in
          lo|"$PRIMARY_IF"|docker*|cni*|flannel*|veth*|kube*) continue ;;
        esac
        PRIV_IF="$IF"
        break
      done

      if [ -z "$PRIV_IF" ]; then
        echo "Nie znaleziono prywatnego interfejsu (primary=$PRIMARY_IF)" >&2
        ip -br link >&2
        exit 1
      fi

      cat > /etc/netplan/60-hetzner-private.yaml <<EOF
      network:
        version: 2
        ethernets:
          $PRIV_IF:
            dhcp4: true
      EOF
      chmod 600 /etc/netplan/60-hetzner-private.yaml
      netplan apply

      # Czekamy aż prywatne IP faktycznie pojawi się na interfejsie
      for i in $(seq 1 30); do
        if ip -4 addr show dev "$PRIV_IF" | grep -qw "${node_ip}"; then
          echo "Prywatne IP ${node_ip} podniesione na $PRIV_IF"
          exit 0
        fi
        sleep 2
      done

      echo "Timeout: ${node_ip} nie pojawiło się na $PRIV_IF" >&2
      ip -4 addr show dev "$PRIV_IF" >&2
      exit 1
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
  - /usr/local/bin/setup-private-net.sh
  - /usr/local/bin/install-k3s.sh
  %{ if role == "server" ~}
  - /usr/local/bin/setup-kubeconfig.sh
  %{ endif ~}
