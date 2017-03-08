#!/usr/bin/env python

import os,re
from argparse import ArgumentParser
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
    opts.add_argument("-P", "--project", default=os.environ['OS_TENANT_NAME'])
    opts.add_argument("-U", "--auth-url", default=os.environ['OS_AUTH_URL'])

    opts.add_argument("-m", "--nameserver")
    opts.add_argument("-k", "--update-key", default=os.getenv('UPDATE_KEY'))
    opts.add_argument("-z", "--zone", default="example.com")
    
    opts.add_argument("-S", "--stack", default="ocp3")
    opts.add_argument("-s", "--subzone", default="control")
    opts.add_argument("-M", "--master-pattern", default="master")
    opts.add_argument("-I", "--infra-pattern", default="infra")


    opts.add_argument("servername")
    opts.add_argument("netname")

    return opts.parse_args()

def floating_ip(server, network):
    entry = None
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

    nova = client.Client("2.0",
                         opts.username,
                         opts.password,
                         opts.project,
                         opts.auth_url)

    
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
