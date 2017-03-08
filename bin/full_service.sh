#!/bin/sh

LB_SPEC=${LB_SPEC:-lb_parameters.yaml}
ZONE=${ZONE:-example.com}
STACK_NAME=${STACK_NAME:-lb-service}

# IMPLICIT - Openstack credentials
# OS_AUTH_URL
# OS_USERNAME
# OS_PASSWORD
# OS_TENANT_NAME
# OS_REGION_NAME


PRIVATE_KEY_FILE=${PRIVATE_KEY_FILE:-~/.ssh/dns_stack_key_rsa}
[ -r $PRIVATE_KEY_FILE ] || (echo no key file $PRIVATE_KEY_FILE && exit 1)

function retry() {
    # cmd = $@
    local POLL_TRY=0
    local POLL_INTERVAL=5
    echo "Trying $@ at $POLL_INTERVAL second intervals"
    local START=$(date +%s)
    while ! $@ ; do
        [ $(($POLL_TRY % 6)) -eq 0 ] && echo -n $(($POLL_TRY * $POLL_INTERVAL)) || echo -n .
        echo -n .
		    sleep $POLL_INTERVAL
		    POLL_TRY=$(($POLL_TRY + 1))
    done
    local END=$(date +%s)
    local DURATION=$(($END - $START))
    echo Done
    echo Completed in $DURATION seconds
}

function stack_complete() {
		# $1 = STACK_NAME
		[ $(openstack stack show $1 -f json | jq '.stack_status' | tr -d \") == "CREATE_COMPLETE" ]
}

# =============================================================================
# MAIN
# =============================================================================

#RHN_CREDENTIALS="-e rhn_credentials.yaml"
set -x
openstack stack create \
          -e ${LB_SPEC} ${RHN_CREDENTIALS} \
          -t haproxy.yaml \
          ${STACK_NAME}
set +x


retry stack_complete ${STACK_NAME}
exit

# get LB host information from OpenStack

# Add A record for LB to DNS

# OPTIONAL
# Get openshift master/infra node name/IP pairs (floating only)

# Install and configure haproxy on LB host


#
# Extract the host information from openstack and create a yaml file with data
# to apply to an inventory template
#
python bin/stack_data.py \
       --zone $ZONE \
       --update-key bKcZ4P2FhWKRQoWtx5F33w== \
       > dns_stack_data.yaml

#
# create an inventory from a template and the stack host information
#
jinja2-2.7 ansible/inventory.j2 dns_stack_data.yaml > inventory

echo "Sleeping for stack instances to stabilize"
sleep 30

#
# Apply the playbook to the OSP instances to create a DNS service
#
ansible-playbook -i inventory \
  --become --user cloud-user --private-key ${PRIVATE_KEY_FILE} \
  --ssh-common-args "-o StrictHostKeyChecking=no" \
  ../dns-service-playbooks/playbooks/bind-server.yml


#
# Add the secondary name servers to the zone as both A and NS records
#
python bin/prime_slave_servers.py
