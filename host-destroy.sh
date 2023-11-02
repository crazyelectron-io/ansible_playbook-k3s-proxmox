#!/bin/bash
# file: k3s-destroy.sh
# synopsis: destroy a cluster (specify the environment 'dev' or 'prod' on the command line)

ansible-playbook host-destroy.yml --inventory ./inventory/$1/hosts.yaml --limit=proxmox -u root --extra-vars "ansible_user=root k3s_environment=$1"
