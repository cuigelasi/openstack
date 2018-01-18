#!/bin/bash
export OS_TOKEN=7027356a188bc8247884
export OS_URL=http://$CONTROLLER_VIP:35357/v3
export OS_IDENTITY_API_VERSION=3
openstack service create --name keystone --description "OpenStack Identity" identity
