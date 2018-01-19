#!/bin/bash
keystone-manage bootstrap --bootstrap-password $ADMIN_PASS --bootstrap-admin-url http://$controller_ip:35357/v3/ --bootstrap-internal-url http://$controller_ip:5000/v3/ --bootstrap-public-url http://$controller_ip:5000/v3/ --bootstrap-region-id RegionOne 

export OS_USERNAME=admin
export OS_PASSWORD=$ADMIN_PASS
export OS_PROJECT_NAME=admin
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_DOMAIN_NAME=Default
export OS_AUTH_URL=http://$controller_ip:35357/v3
export OS_IDENTITY_API_VERSION=3

openstack project create --domain default --description "Service Project" service;
openstack project create --domain default --description "Demo Project" demo;
openstack user create --domain default --password $DEMO_PASS demo;
openstack role create user;
openstack role add --project demo --user demo user

unset OS_AUTH_URL OS_PASSWORD
