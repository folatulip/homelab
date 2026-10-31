output "name" { value = proxmox_virtual_environment_vm.this.name }
output "ip"   { value = split("/", var.ip)[0] }