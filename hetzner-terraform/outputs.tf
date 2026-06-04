output "control_plane_ip" {
  description = "Public IP of the k3s control-plane node"
  value       = hcloud_server.control_plane.ipv4_address
}

output "worker_ips" {
  description = "Public IPs of worker nodes"
  value       = [for w in hcloud_server.worker : w.ipv4_address]
}

output "ssh_command" {
  description = "SSH command to connect to control plane"
  value       = "ssh root@${hcloud_server.control_plane.ipv4_address}"
}

output "kubeconfig_command" {
  description = "Command to fetch kubeconfig from control plane"
  value       = "ssh root@${hcloud_server.control_plane.ipv4_address} cat /root/.kube/config > ~/.kube/k3s-test.yaml && export KUBECONFIG=~/.kube/k3s-test.yaml"
}

output "k3s_token" {
  description = "k3s cluster token (sensitive)"
  value       = random_password.k3s_token.result
  sensitive   = true
}
