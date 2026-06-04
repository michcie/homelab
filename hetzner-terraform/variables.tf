variable "hcloud_token" {
  description = "Hetzner Cloud API token"
  type        = string
  sensitive   = true
}

variable "ssh_key_name" {
  description = "Name of the existing SSH key in Hetzner Cloud (Security → SSH Keys)"
  type        = string
  default     = "michcie"
}

variable "location" {
  description = "Hetzner datacenter location"
  type        = string
  default     = "nbg1"
}

variable "server_type" {
  description = "Hetzner server type for control-plane node"
  type        = string
  default     = "cpx22" # 2 vCPU, 4 GB RAM – enough for single-node k3s test
}

variable "worker_count" {
  description = "Number of worker nodes (0 = single-node cluster)"
  type        = number
  default     = 0
}

variable "worker_server_type" {
  description = "Hetzner server type for worker nodes"
  type        = string
  default     = "cx22"
}

variable "k3s_version" {
  description = "k3s version to install (leave empty for latest)"
  type        = string
  default     = ""
}

variable "network_cidr" {
  description = "CIDR for the private network"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidr" {
  description = "CIDR for the private subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "cluster_name" {
  description = "Name prefix for all resources"
  type        = string
  default     = "k3s-test"
}
