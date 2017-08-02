#!/usr/bin/python

from ansible.module_utils.basic import *

import subprocess,json

def ips(net_string):
    ips = {}
    for net_record in net_string.split('; '):
        (net, ip_string) = net_record.split("=")
        ip_list = ip_string.split(", ")
        for ip in ip_list:
            try:
                if ip in ansible_facts['floating_ips']:
                    iptype = "floating"
                else:
                    iptype = "fixed"
            except Error e:
                iptype = e

            ips[ip] = dict(network = net, type = iptype)
            
    return ips
    
def main():
    module = AnsibleModule(argument_spec=dict(
        pattern=dict(required=True, type='str'),
    ))

    command = [
        'openstack', 'server', 'list', '-f', 'json',
        '--name', module.params.get('pattern')
    ]

    process = subprocess.Popen(command,
                               stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE)
    stdout, stderr = process.communicate()

    host_records = json.loads(stdout)
    servers = {hr['Name']: dict(addresses = ips(hr['Networks'])) for hr in host_records}

    exit_code = process.wait()
    if exit_code == 0:
        module.exit_json(
            msg="Servers queried successfully.",
            ansible_facts=dict(servers = servers),
            stdout=stdout,
            stderr=stderr,
            rc=exit_code,
            changed=False)
    else:
        module.fail_json(
            msg="Server query failed.",
            stdout=stdout,
            stderr=stderr,
            rc=exit_code)

if __name__ == '__main__':
    main()
