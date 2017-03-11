#!/bin/sh


function parse_args() {
		while getopts "d:h:n:N:S:R:k:K:P:z:" arg ; do
				case $arg in
						h) LB_HOSTNAME=$OPTARG ;;
						z) ZONE=$OPTARG ;;

						d) DNS_SERVER=$OPTARG ;;
						k) DNS_UPDATE_KEY=$OPTARG ;;
						
						# Stack creation values
						N) STACK_NAME=$OPTARG ;;
            e) EXTERNAL_NETWORK_NAME=$OPTARG ;;
						n) PRIVATE_NETWORK_NAME=$OPTARG ;;
						s) PRIVATE_SUBNET_NAME=$OPTARG ;;
            S) SERVER_SPEC=$OPTARG ;;
            R) RHN_CREDENTIALS_SPEC=$OPTARG ;;
            K) SSH_KEY_NAME=$OPTARG ;;
            P) PRIVATE_KEY_FILE=$OPTARG ;;
				esac
		done
}

function set_defaults() {
		LB_HOSTNAME=${LB_HOSTNAME:-lb}
		ZONE=${ZONE:-example.com}

    # == OSP settings ==
    #
    # Public network to attach to
    EXTERNAL_NETWORK_NAME=${EXTERNAL_NETWORK_NAME:-public_network}
    PRIVATE_NETWORK_NAME=${PRIVATE_NETWORK_NAME:-dns-network}
    PRIVATE_SUBNET_NAME=${PRIVATE_SUBNET_NAME:-dns-subnet}

    # OSP Instance values
    #   flavor
    #   image
    #   ssh_user
    SERVER_SPEC=${SERVER_SPEC:-env_server.yaml}

    SSH_KEY_NAME=${SSH_KEY_NAME:-ocp3}
    STACK_NAME=${STACK_NAME:-lb-service}

    # RHN Credentials: no default
    #  rhn_username
    #  rhn_password
    #  rhn_pool_id
    #  sat6_organization
    #  sat6_activationkey
    #RHN_CREDENTIALS_SPEC=${RHN_CREDENTIALS_SPEC:-rhn_credentials.yaml}

    PRIVATE_KEY_FILE=${PRIVATE_KEY_FILE:-~/.ssh/id_rsa}
}

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

function create_stack() {

    # RHN credentials are only needed for RHEL images in the SERVER SPEC
    [ -z "$RHN_CREDENTIALS_SPEC" ] || local RHN_CREDENTIALS_ARG="-e $RHN_CREDENTIALS_SPEC"

    openstack stack create \
              -e ${SERVER_SPEC} \
              ${RHN_CREDENTIALS_ARG} \
              --parameter external_network=${EXTERNAL_NETWORK_NAME} \
              --parameter service_network=${PRIVATE_NETWORK_NAME} \
              --parameter service_subnet=${PRIVATE_SUBNET_NAME} \
              --parameter domain_name=${ZONE} \
              --parameter hostname=$LB_HOSTNAME \
              --parameter ssh_key_name=${SSH_KEY_NAME} \
              -t lb_service.yaml ${STACK_NAME}
}

function stack_status() {
		openstack stack show $1 -f json | jq '.stack_status' | tr -d \"
}

function stack_complete() {
		local STATUS=$(stack_status $1)
		[ ${STATUS} == 'CREATE_COMPLETE' -o ${STATUS} == 'CREATE_FAILED' ]
}

function ssh_user_from_stack() {
  openstack stack show $1 -f json | jq '.parameters.ssh_user'
}

function generate_inventory() {
    # Write a YAML file as input to jinja to create the inventory
    # master and slave name/ip information comes from OSP

		python bin/lb_info.py ${LB_HOSTNAME}.${ZONE} > stack_data.yaml
		jinja2-2.7 inventory.j2 stack_data.yaml > inventory
}

function configure_lb_services() {
		SSH_USER_NAME=$(ssh_user_from_stack ${STACK_NAME})

		export ANSIBLE_HOST_KEY_CHECKING=False
		ansible-playbook \
				-i inventory \
				--become --user ${SSH_USER_NAME} \
				--private-key ${PRIVATE_KEY_FILE} \
				playbooks/haproxy.yml
}

# ============================================================================
# MAIN
# ============================================================================

parse_args $@
set_defaults

create_stack

retry stack_complete ${STACK_NAME}

if [ "$(stack_status ${STACK_NAME})" == "CREATE_FAILED" ] ; then
		echo "Create failed"
		exit 1
fi

generate_inventory
configure_lb_services

LB_IPADDRESS=$(grep lb_address stack_data.yaml | awk '{print $2}')

if [ ! -z "$DNS_SERVER" ] ; then
		python ../dns-service-heat/bin/add_a_record.py \
					 -s ${DNS_SERVER} -k "${DNS_UPDATE_KEY}" -z ${ZONE} \
					 ${LB_HOSTNAME} ${LB_IPADDRESS} 

		python ../dns-service-heat/bin/add_a_record.py \
					 -s ${DNS_SERVER} -k "${DNS_UPDATE_KEY}" -z ${ZONE} \
					 devs ${LB_IPADDRESS} 

		python ../dns-service-heat/bin/add_a_record.py \
					 -s ${DNS_SERVER} -k "${DNS_UPDATE_KEY}" -z ${ZONE} \
					 '*.apps' ${LB_IPADDRESS} 

fi
