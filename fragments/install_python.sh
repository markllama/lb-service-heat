#!/bin/sh
#
# Ensure that Python is installed for Ansible
#
function retry() {
    for I in {1..5} ; do
        echo "try $I: $@"
        $@ && return || true
        echo "waiting 2 sec. to try again"
        sleep 2
    done
    echo "failed $I tries: $@"
    false
}

[ -f /etc/fedora-release ] && retry dnf install -y python python-dnf libselinux-python
