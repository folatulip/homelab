variable "name"      { type = string }
variable "node"      { type = string }
variable "vm_id"     { type = number }
variable "template_id" { type = number }
variable "cores"     { 
    type = number 
    default = 2 
}
variable "memory"    { 
    type = number 
    default = 2048 
}
variable "disk_size" { 
    type = number 
    default = 20 
}
variable "ip"        { type = string }
variable "gateway"   { type = string }
variable "tags"      { 
    type = list(string) 
default = [] 
}
