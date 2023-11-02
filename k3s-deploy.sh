#!/bin/bash
# file: k3s-deploy.sh
# synopsis: Deploy K3s cluster (specify the environment 'dev' or 'prod' on the command line), optionally with VM nodes

shopt -s nocasematch

if [ "$#" -lt 3 ]
then
  echo "Error: no arguments supplied."
  echo " Usage: $0 [ENV] [USER] [SCOPE]"
  echo "  [ENV]   = Environment, e.g. prod"
  echo "  [USER]  = Ansible user, e.g. mainuser"
  echo "  [SCOPE] = ALL or HOST or CLUSTER"
  exit 1
fi

SCOPE=$3

if [[ ${SCOPE} = "host" ]] || [[ ${SCOPE} = "all" ]]
then
  ansible-playbook deploy-hosts.yaml --inventory ./inventory/$1 -u root --extra-vars "ansible_user=root k3s_environment=$1"
fi

if [[ ${SCOPE} = "cluster" ]] || [[ ${SCOPE} = "all" ]]
then
  ansible-playbook deploy-cluster.yaml --inventory ./inventory/$1 --key-file $HOME/.ssh/$2_key -u $2 --extra-vars k3s_environment=$1
fi
