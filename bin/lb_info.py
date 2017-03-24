#!/usr/bin/env python

import os,re
from argparse import ArgumentParser

from keystoneclient.auth.identity import v3 as ks_v3
from keystoneclient import session as ks_session
from keystoneclient.v3 import client as ksclient

from novaclient import client as novaclient

# python2-dns
import dns.query
import dns.tsigkeyring
import dns.update
import yaml

def parse_cli():
    opts = ArgumentParser()
    opts.add_argument("-u", "--username", default=os.environ['OS_USERNAME'])
    opts.add_argument("-p", "--password", default=os.environ['OS_PASSWORD'])
    opts.add_argument("-P", "--project-id", default=os.environ['OS_PROJECT_NAME'])
    opts.add_argument("-d", "--user-domain", default=os.getenv('OS_USER_DOMAIN_NAME'))
    opts.add_argument("-U", "--auth-url", default=os.environ['OS_AUTH_URL'])

    opts.add_argument("-m", "--nameserver")
    opts.add_argument("-k", "--update-key", default=os.getenv('UPDATE_KEY'))
    opts.add_argument("-z", "--zone", default="example.com")
    
    opts.add_argument("-S", "--stack", default="ocp3")
    opts.add_argument("-s", "--subzone", default="control")
    opts.add_argument("-M", "--master-pattern", default="master")
    opts.add_argument("-I", "--infra-pattern", default="infra")
    
    opts.add_argument("-n", "--netname", default=None)

    opts.add_argument("servername")

    return opts.parse_args()

def floating_ip(server, network=None):
    entry = None
    if network == None:
        network = server.addresses.keys()[0]
    for interface in server.addresses[network]:
        if interface['OS-EXT-IPS:type'] == 'floating':
            entry = {"name": server.name, "address": interface['addr']}
    return entry

def host_part(fqdn,zone):
    zone_re = re.compile("(.*).(%s)$" % zone)
    response = zone_re.match(fqdn)
    return response.groups()[0]
    
def add_a_record(name,zone,ipv4addr,master,key):
    keyring = dns.tsigkeyring.from_text({'update-key': key})
    update = dns.update.Update(zone, keyring=keyring)
    update.replace(name, 300, 'a', ipv4addr)
    response = dns.query.tcp(update, master)
    return response

if __name__ == "__main__":
    opts = parse_cli()

    auth = ks_v3.Password(auth_url=opts.auth_url,
                       username=opts.username,
                       password=opts.password,
                       user_domain_name=opts.user_domain,
                       project_id=opts.project_id)
    sess = ks_session.Session(auth=auth)
    keystone = ksclient.Client(session=sess)
    nova = novaclient.Client(2, session=keystone.session)
    
    host = nova.servers.find(name=opts.servername)

    host_info = floating_ip(host, opts.netname)
    
    # Add the loadbalancer to the DNS database
    if opts.nameserver:
        record = floating_ip(host, opts.netname)
        add_a_record(
            host_part(record['name'], opts.zone),
            opts.zone,
            record['address'],
            opts.nameserver,
            opts.update_key
        )


    # find the masters and infra servers

    print "lb_address: %s" % host_info['address']
