#!/bin/bash -e

case $1 in
"destroy")
    ansible-playbook setup-infra.yml -e operation=destroy
    ;;
"create")
    ansible-playbook setup-infra.yml -e operation=create
    ansible-playbook -i host.ini ansible-kind.yml -u ubuntu --key-file '~/.ssh/id_flexi'
    ;;
"bootstrap")
    ansible-playbook setup-infra.yml -e operation=create
    ansible-playbook -i host.ini ansible-kind.yml -u ubuntu --key-file '~/.ssh/id_flexi'
    ansible-playbook setup-infra.yml -e operation=destroy
    ;;
esac
