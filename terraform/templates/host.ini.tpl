[servers]
kind-capi ansible_host=${kind_floating_ip}

[servers:vars]
ansible_user=${ansible_user}
vm_private_key_file=${vm_private_key_file}
ansible_ssh_common_args="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"