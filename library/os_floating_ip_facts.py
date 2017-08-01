#!/usr/bin/python

from ansible.module_utils.basic import *

import subprocess,json
    
def main():
    module = AnsibleModule(argument_spec={})

    command = [ 'openstack', 'floating', 'ip', 'list', '-f', 'json' ]
    process = subprocess.Popen(command,
                               stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE)
    stdout, stderr = process.communicate()
    exit_code = process.wait()

    ip_records = json.loads(stdout)
    floating_ips = {ip['Floating IP Address']: dict(
        fixed_ip = ip['Fixed IP Address'],
        port = ip['Port'],
        id = ip['ID']
    ) for ip in ip_records}

    if exit_code == 0:
        module.exit_json(
            msg="OpenStack Floating IPs queried successfully.",
            ansible_facts=dict(floating_ips = floating_ips),
            stdout=stdout,
            stderr=stderr,
            rc=exit_code,
            changed=False)
    else:
        module.fail_json(
            msg="OpenStack Floating IP  query failed.",
            stdout=stdout,
            stderr=stderr,
            rc=exit_code)

if __name__ == '__main__':
    main()
