#!/bin/bash
# file: k3s-reset.sh [ENV] [USER]
# synopsis: reset en remove the cluster software and configuration (specify the environment 'dev' or 'prod' on the command line)

if [ "$#" -lt 2 ]
then
  echo "Error: no arguments supplied."
  echo " Usage: $0 [ENV] [USER]"
  echo "  [ENV] = Environment, e.g. prod"
  echo "  [USER] = Ansible user, e.g. mainuser"
  exit 1
fi

ansible-playbook k3s-reset.yaml --inventory ./inventory/$1 --key-file $HOME/.ssh/$2_key -u $2 --extra-vars k3s_environment=$1
# ansible-playbook reboot.yaml -i inventory/$1 --limit=k3s-$1-* --key-file $HOME/.ssh/beheerder_key
