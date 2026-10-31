variable "pm_endpoint" { type = string }
variable "pm_api_token" { type = string }
variable "nas_passwords" {
  description = "Proxmox NAS storage id => SMB password."
  type        = map(string)
  default     = {}
  sensitive   = true
}
