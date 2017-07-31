#!/usr/bin/python

from ansible.module_utils.basic import *

import subprocess,json


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
    exit_code = process.wait()
    if exit_code == 0:
        module.exit_json(
            msg="Servers queried successfully.",
            ansible_facts=dict(),
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
