variable "tenant_name" {
  description = "FlexiHPC project Name"
}

variable "key_pair" {
  description = "FlexiHPC SSH Key Pair name"
}

variable "key_file" {
  description = "Path to local SSH private key associated with Flexi key_pair, used for provisioning"
}

variable "kind_flavor_id" {
  description = "FlexiHPC Flavor ID, Defaults to devtest1.1cpu1ram"
  default     = "ee55c523-9803-4296-91be-1c34e986baaa" 
}

variable "kind_image_id" {
  description = "FlexiHPC Image ID, Defaults to Ubuntu-Jammy-22.04"
  default     = "1a0480d1-55c8-4fd7-8c7a-8c26e52d8cbd" 
}

variable "kind_security_groups" {
  description = "A list of security groups to add to the K8 VM's"
  default     = ["default"] 
}

variable "vm_user" {
  description = "FlexiHPC VM user"
  default = "ubuntu"
}

variable "extra_public_keys" {
  description = "Additional SSH public keys to add to the authorized_keys file on provisioned nodes"
  type = list(string)
  default = []
}
