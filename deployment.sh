#!/bin/bash -e

case $1 in
"destroy")
    ansible-playbook setup-infra.yml -e operation=destroy
    ;;
"create")
    ansible-playbook setup-infra.yml -e operation=create
    ansible-playbook -i host.ini ansible-kind.yml -u ${TF_VAR_vm_user} --key-file '${TF_VAR_key_file}'
    ;;
"bootstrap")
    ansible-playbook setup-infra.yml -e operation=create
    ansible-playbook -i host.ini ansible-kind.yml -u ${TF_VAR_vm_user} --key-file '${TF_VAR_key_file}'
    ansible-playbook setup-infra.yml -e operation=destroy
    ;;
esac
