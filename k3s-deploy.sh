#!/bin/bash
# file: k3s-deploy.sh
# synopsis: deploy a cluster (specify the environment 'dev' or 'prod' on the command line)

if [ "$#" -lt 3 ]
then
  echo "Error: no arguments supplied."
  echo " Usage: $0 [ENV] [USER] AAL|HOST|CLUSTER"
  echo "  [ENV] = Environment, e.g. prod"
  echo "  [USER] = Ansible user, e.g. mainuser"
  exit 1
fi

# ansible-playbook deploy-hosts.yaml --inventory ./inventory/$1 -u root --extra-vars "ansible_user=root k3s_environment=$1"
ansible-playbook deploy-cluster.yaml --inventory ./inventory/$1 --key-file $HOME/.ssh/$2_key -u $2 --extra-vars k3s_environment=$1
