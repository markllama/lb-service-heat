#!/bin/sh

LB_SPEC=${LB_SPEC:-lb_parameters.yaml}
LB_HOSTNAME=${LB_HOSTNAME:-lb}
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
					--parameter hostname=${LB_HOSTNAME} \
					--parameter domain_name=${ZONE} \
          -t haproxy.yaml \
          ${STACK_NAME}
set +x


retry stack_complete ${STACK_NAME}


# get LB host information from OpenStack
python bin/lb_info.py ${LB_HOSTNAME}.${ZONE} > lb_stack_data.yaml

jinja2-2.7 inventory.j2 lb_stack_data.yaml > inventory

# Add A record for LB to DNS
if [ -z "$DNS_UPDATE_KEY" ] then
	 echo "NO DNS KEY VARIABLE SET"
	 exit 1
fi
	 
python ../dns-service-heat/bin/add_a_record.py \
			 --server ${DNS_SERVER} \
			 --zone ${ZONE} \
			 ${LB_HOSTNAME}.${ZONE} $(cut -d' ' -f2 lb_stack_data.yaml)

# OPTIONAL
# Get openshift master/infra node name/IP pairs (floating only)

# Install and configure haproxy on LB host


exits
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
