#!/bin/sh

OPENSHIFT_INVENTORY=/root/hosts-openshift.inv
TOOLING_INVENTORY=/root/tooling_inventory

# label openshift nodes, generate an inventory
#cd /root/svt/openshift_tooling/openshift_labeler
#ansible-playbook -vvv -i ${OPENSHIFT_INVENTORY} openshift_label.yml
#if [[ $? != 0 ]]; then
#  echo "1" > /tmp/tooling_status
#else
#  echo "0" > /tmp/tooling_status
#fi
#
#exit

cd /root/svt/openshift_tooling/pbench
./setup_pbench_pods.sh
if [[ $? != 0 ]]; then
  echo "1" > /tmp/tooling_status
else
  echo "0" > /tmp/tooling_status
fi

