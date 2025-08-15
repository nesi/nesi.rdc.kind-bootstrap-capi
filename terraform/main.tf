# Create services instance
resource "openstack_compute_instance_v2" "kind_instance" {
  name            = "capi-seed-vm"
  flavor_id       = var.kind_flavor_id
  image_id        = var.kind_image_id
  key_pair        = var.key_pair
  security_groups = var.kind_security_groups

  network {
    name = var.tenant_name
  }
}

# Create floating ip
resource "openstack_networking_floatingip_v2" "kind_floating_ip" {
  pool  = "external"
}

# Assign floating ip
resource "openstack_compute_floatingip_associate_v2" "kind_floating_ip_association" {
  floating_ip  = openstack_networking_floatingip_v2.kind_floating_ip.address
  instance_id  = openstack_compute_instance_v2.kind_instance.id
}

# add extra public keys to services instance
resource "null_resource" "services_extra_keys" {
  depends_on = [openstack_compute_floatingip_associate_v2.kind_floating_ip_association]
  count = length(var.extra_public_keys) > 0 ? 1 : 0

  connection {
    user = var.vm_user
    private_key = file(var.key_file)
    host = "${openstack_networking_floatingip_v2.kind_floating_ip.address}"
  }

  provisioner "remote-exec" {
    inline = [for pkey in var.extra_public_keys : "echo ${pkey} >> $HOME/.ssh/authorized_keys"]
  }
}


# Generate ansible hosts
locals {
  host_ini_all = templatefile("${path.module}/templates/all-hosts.tpl", {
    kind_floating_ip = openstack_networking_floatingip_v2.kind_floating_ip.address,
    vm_private_key_file = var.key_file
  })
}

# Generate ansible host.ini file
locals {
  host_ini_content = templatefile("${path.module}/templates/host.ini.tpl", {
    kind_floating_ip = openstack_networking_floatingip_v2.kind_floating_ip.address,
    vm_private_key_file = var.key_file
  })
}

resource "local_file" "host_ini" {
  filename = "../host.ini"
  content  = "${local.host_ini_all}\n${local.host_ini_content}"
  file_permission = "0644"
}
