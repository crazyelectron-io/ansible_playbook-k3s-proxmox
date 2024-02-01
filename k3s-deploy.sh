#!/bin/bash
# file: k3s-deploy.sh
# synopsis: Deploy K3s cluster (specify the environment 'dev' or 'prod' on the command line), optionally with VM nodes

shopt -s nocasematch
DEBUG=""

if [ "$#" -ne 2 ]
then
  echo "Error: no arguments supplied."
  echo " Usage: $0 [ENV] [SCOPE]"
  echo "  [ENV]   = Environment, e.g. prod or dev"
  echo "  [SCOPE] = ALL, CLUSTER, APPS, OPENHAB"
  echo " "
  echo "Example:"
  echo "   $0 prod openhab  - installs OpenHAB configuration"
  echo "   $0 prod apps - installs the applications"
  exit 1
fi

SCOPE=$2

RC=0
# if [[ ${SCOPE} = "cluster" ]] || [[ ${SCOPE} = "all" ]]
# then
#   ansible-playbook ${DEBUG} deploy-cluster.yaml --inventory ./inventory/$1 --key-file $HOME/.ssh/beheerder_key -u beheerder --extra-vars k3s_environment=$1
#   if [ $? -ne 0 ]; then
#     exit 1
#   fi
# fi

if [[ ${SCOPE} = "apps" ]] || [[ ${SCOPE} = "all" ]]
then
  ansible-playbook ${DEBUG} deploy-apps.yaml --inventory ./inventory/$1 --extra-vars k3s_environment=$1
  if [ $? -ne 0 ]; then
    exit 1
  fi
fi

if [[ ${SCOPE} = "openhab" ]] || [[ ${SCOPE} = "all" ]]
then
  ansible-playbook ${DEBUG} deploy-openhab.yaml --inventory ./inventory/$1
  if [ $? -ne 0 ]; then
    exit 1
  fi
fi
