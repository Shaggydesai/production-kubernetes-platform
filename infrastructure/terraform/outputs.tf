output "node_ips" {
  description = "Node name to IP address."
  value       = { for k, v in var.nodes : k => v.ip }
}

output "control_plane_ip" {
  value = one([for k, v in var.nodes : v.ip if v.role == "control-plane"])
}

output "control_plane_endpoint" {
  value = var.control_plane_endpoint
}

output "ssh_commands" {
  description = "Copy-paste reachability check."
  value       = [for k, v in var.nodes : "ssh ${var.admin_user}@${v.ip}"]
}

output "ansible_inventory" {
  description = <<-EOT
    Rendered Ansible inventory. Write it with:

      terraform output -raw ansible_inventory > ../ansible/inventory/lab.yml

    Generated rather than hand-maintained so the inventory cannot drift from the
    guests that actually exist - which is how you end up running a playbook
    against an address nothing answers on.
  EOT
  value = templatefile("${path.module}/templates/inventory.yaml.tftpl", {
    nodes                  = var.nodes
    admin_user             = var.admin_user
    control_plane_endpoint = var.control_plane_endpoint
    pod_subnet             = "10.244.0.0/16"
    service_subnet         = "10.96.0.0/12"
  })
}
