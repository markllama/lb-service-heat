#!/usr/bin/env python

import os,re,sys
from argparse import ArgumentParser
from keystoneauth1 import loading
from keystoneauth1 import session
from novaclient import client

# python2-dns
import dns.query
import dns.tsigkeyring
import dns.update
import yaml

def parse_cli():
    opts = ArgumentParser()
    opts.add_argument("-u", "--username", default=os.environ['OS_USERNAME'])
    opts.add_argument("-p", "--password", default=os.environ['OS_PASSWORD'])
    opts.add_argument("-P", "--project", default=os.environ['OS_PROJECT_ID'])
    opts.add_argument("-D", "--domain", default=os.environ['OS_USER_DOMAIN_NAME'])
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

    loader = loading.get_plugin_loader('password')
    auth = loader.load_from_options(auth_url=opts.auth_url,
                                    username=opts.username,
                                    password=opts.password,
                                    user_domain_name=opts.domain,
                                    project_id=opts.project)
    sess = session.Session(auth=auth)
    nova = client.Client("2", session=sess)

    host = nova.servers.find(name=opts.servername)

    host_info = floating_ip(host, opts.netname)

    # Add the loadbalancer to the DNS database
    if opts.nameserver:
        record = floating_ip(host, opts.netname)
        response = add_a_record(
            host_part(record['name'], opts.zone),
            opts.zone,
            record['address'],
            opts.nameserver,
            opts.update_key
        )

    # find the masters and infra servers

    print "lb_address: %s" % host_info['address']
