[servers]
kind-capi ansible_host=${kind_floating_ip}

[servers:vars]
vm_private_key_file=${vm_private_key_file}
ansible_ssh_common_args="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"