resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/inventory.tpl", {
    server_ip = hcloud_server.control_plane.ipv4_address
  })
  filename        = "${path.module}/../ansible/inventory.yml"
  file_permission = "0644"
}
