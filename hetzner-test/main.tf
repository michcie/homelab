locals {
  cp_private_ip = cidrhost(var.subnet_cidr, 10)
}

# --- SSH Key ---

data "hcloud_ssh_key" "default" {
  name = var.ssh_key_name
}

# --- Network ---

resource "hcloud_network" "main" {
  name     = "${var.cluster_name}-net"
  ip_range = var.network_cidr
}

resource "hcloud_network_subnet" "main" {
  type         = "cloud"
  network_id   = hcloud_network.main.id
  network_zone = "eu-central"
  ip_range     = var.subnet_cidr
}

# --- Firewall ---

resource "hcloud_firewall" "control_plane" {
  name = "${var.cluster_name}-cp-fw"

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "6443"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction  = "in"
    protocol   = "icmp"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "80"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "443"
    source_ips = ["0.0.0.0/0", "::/0"]
  }
}

resource "hcloud_firewall" "worker" {
  count = var.worker_count > 0 ? 1 : 0
  name  = "${var.cluster_name}-worker-fw"

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction  = "in"
    protocol   = "icmp"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  # Workery gadają z control plane przez sieć prywatną
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "any"
    source_ips = [var.network_cidr]
  }

  rule {
    direction  = "in"
    protocol   = "udp"
    port       = "any"
    source_ips = [var.network_cidr]
  }
}

# --- k3s token ---

resource "random_password" "k3s_token" {
  length  = 48
  special = false
}

# --- Control Plane ---

resource "hcloud_server" "control_plane" {
  name         = "${var.cluster_name}-cp"
  server_type  = var.server_type
  image        = "ubuntu-24.04"
  location     = var.location
  ssh_keys     = [data.hcloud_ssh_key.default.id]
  firewall_ids = [hcloud_firewall.control_plane.id]

  network {
    network_id = hcloud_network.main.id
    ip         = local.cp_private_ip
  }

  user_data = templatefile("${path.module}/cloud-init-server.yaml.tpl", {
    role             = "server"
    k3s_token        = random_password.k3s_token.result
    k3s_version      = var.k3s_version
    node_ip          = local.cp_private_ip
    control_plane_ip = local.cp_private_ip
    cluster_name     = var.cluster_name
  })

  depends_on = [hcloud_network_subnet.main]

  lifecycle {
    ignore_changes = [user_data]
  }
}

# --- Workers ---

resource "hcloud_server" "worker" {
  count        = var.worker_count
  name         = "${var.cluster_name}-worker-${count.index + 1}"
  server_type  = var.worker_server_type
  image        = "ubuntu-24.04"
  location     = var.location
  ssh_keys     = [data.hcloud_ssh_key.default.id]
  firewall_ids = var.worker_count > 0 ? [hcloud_firewall.worker[0].id] : []

  network {
    network_id = hcloud_network.main.id
    ip         = cidrhost(var.subnet_cidr, 20 + count.index)
  }

  user_data = templatefile("${path.module}/cloud-init-server.yaml.tpl", {
    role             = "agent"
    k3s_token        = random_password.k3s_token.result
    k3s_version      = var.k3s_version
    node_ip          = cidrhost(var.subnet_cidr, 20 + count.index)
    control_plane_ip = local.cp_private_ip
    cluster_name     = var.cluster_name
  })

  depends_on = [
    hcloud_network_subnet.main,
    hcloud_server.control_plane,
  ]

  lifecycle {
    ignore_changes = [user_data]
  }
}
