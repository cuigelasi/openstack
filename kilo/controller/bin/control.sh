#!/bin/bash


## get installation package absolute path
getPath()
{
    this_dir=`pwd`
    dirname $0 | grep "^/" >/dev/null
    if [ $? -eq 0 ]; then
        this_dir=`dirname $0`
    else
        dirname $0 | grep "^\." >/dev/null
        retval=$?
        if [ $retval -eq 0 ]; then
            this_dir=`dirname $0 | sed "s#^.#$this_dir#"`
        else
            this_dir=`dirname $0 | sed "s#^#$this_dir/#"`
        fi
    fi
    echo `dirname $this_dir`
}




## configure service
INSTALL_PACKAGE_PATH=`getPath`

CONF_PATH=$INSTALL_PACKAGE_PATH/confs
CODE_PATH=$INSTALL_PACKAGE_PATH/codes
PIP_PATH=$INSTALL_PACKAGE_PATH/pip
YUM_PATH=$INSTALL_PACKAGE_PATH/local_yum

EXPECT=/usr/bin/expect
# hostname
HOSTNAME=controller
# openstack admin password
ADMIN_PASS=123qwe
# database root password
DB_PASS=123qwe
# local controller ip
LOCAL_C_IP=172.16.5.137
# local tunnel ip
LOCAL_T_IP=192.168.5.137
# local external interface
LOCAL_E_INTERFACE=eth1
# Verify/
if  [ ! -n "$ADMIN_PASS" ] ;then
    echo "Inform: Variable ADMIN_PASS is set to default for empty"
    ADMIN_PASS=123qwe
    echo "ADMIN_PASS=$ADMIN_PASS"
fi
if  [ ! -n "$DB_PASS" ] ;then
    echo "Inform: Variable DB_PASS is set to default for empty"
    DB_PASS=123qwe
    echo "DB_PASS=$DB_PASS"
fi
if  [ ! -n "$LOCAL_C_IP" ] ;then
    echo "Inform: Variable LOCAL_C_IP is set to default for empty"
    exit 1
fi
if  [ ! -n "$LOCAL_T_IP" ] ;then
    echo "Inform: Variable LOCAL_T_IP is set to default for empty"
    exit 1
fi
if  [ ! -n "$LOCAL_E_INTERFACE" ] ;then
    echo "Inform: Variable LOCAL_E_INTERFACE is set to default for empty"
fi

# local yum 
mkdir -p /root/centos_yum.repo
mv /etc/yum.repos.d/* /root/centos_yum.repo
mkdir -p /root/local_yum
\cp -r $YUM_PATH/* /root/local_yum
rm -f /etc/yum.repos.d/local.repo
touch /etc/yum.repos.d/local.repo
cat >> /etc/yum.repos.d/local.repo <<EOF       
[local_server]
name=This is a local repo
baseurl=file:///root/local_yum
enabled=1
gpgcheck=0
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7
EOF

## install package
#yum clean all
yum -y update
yum -y install expect crudini
yum -y install python-openstackclient openstack-selinux
yum -y install mariadb mariadb-server MySQL-python
yum -y install rabbitmq-server
yum -y install memcached python-memcached
yum -y install openstack-keystone httpd mod_wsgi 
yum -y install openstack-glance python-glance python-glanceclient
yum -y install openstack-nova-api openstack-nova-cert openstack-nova-conductor openstack-nova-console openstack-nova-scheduler python-novaclient
yum -y install spice-html5 openstack-nova-spicehtml5proxy
yum -y install openstack-neutron openstack-neutron-ml2 openstack-neutron-openvswitch python-neutronclient which
yum -y install openstack-dashboard 
yum -y install openstack-cinder python-cinderclient python-oslo-db
yum -y install qemu lvm2
yum -y install targetcli python-oslo-log
yum -y install python-pip

# Upgrade python package
mkdir -p /var/python/packages/
\cp -r $PIP_PATH/* /var/python/packages/
pip install --index-url=file:///var/python/packages/simple/ --upgrade pip
pip install --index-url=file:///var/python/packages/simple/ django-pyscss==2.0.2



# disable selinux
echo "disable selinux..."
setenforce 0
sed -i "s/^SELINUX=.*/SELINUX=disabled/" /etc/selinux/config
echo -e "end.\n"

# enable ports
# chronyd:123/udp  httpd:80/tcp  mariadb:3306/tcp,4444/tcp,4567/tcp,4567/udp,4568/tcp
# rabbitmq:4369/tcp,5672/tcp,25672/tcp  memcached:11211/tcp  keystone:5000/tcp,35357/tcp
# glance:9292/tcp,9191/tcp  nova:8773-8775/tcp  spice:6082/tcp  neutron:9696/tcp
# cinder:8776/tcp  openvswitch:4789/udp
echo "enable firewall ports..."
firewall-cmd --zone=public --add-port=123/udp --add-port=80/tcp --add-port=3306/tcp --add-port=4444/tcp \
    --add-port=4567/tcp --add-port=4567/udp --add-port=4568/tcp --add-port=4369/tcp --add-port=5672/tcp \
	--add-port=25672/tcp --add-port=11211/tcp --add-port=5000/tcp --add-port=35357/tcp --add-port=9292/tcp \
	--add-port=9191/tcp --add-port=8773-8775/tcp --add-port=6082/tcp --add-port=9696/tcp --add-port=8776/tcp \
	--add-port=4789/udp --permanent
firewall-cmd --reload
echo -e "end.\n"

# chronyd
echo "start chronyd..."
ping -c 3 time1.aliyun.com
if [ $? -eq 0 ]; then
	ntpdate time1.aliyun.com
    hwclock -w
fi

sed -i "s/^server/#server/g" /etc/chrony.conf
sed -i "/^#allow/a\allow" /etc/chrony.conf
sed -i "s/^#local/local/g" /etc/chrony.conf
systemctl enable chronyd.service
systemctl restart chronyd.service
echo -e "end.\n"

# sysctl
echo "config sysctl..."
echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
echo "net.ipv4.conf.all.rp_filter = 0" >> /etc/sysctl.conf
echo "net.ipv4.conf.default.rp_filter = 0" >> /etc/sysctl.conf
sysctl -p
echo -e "end.\n"

# database
echo "start database..." 
crudini --set /etc/my.cnf.d/mariadb-server.cnf mysqld bind-address $LOCAL_C_IP
crudini --set /etc/my.cnf.d/mariadb-server.cnf mysqld default-storage-engine innodb
crudini --set /etc/my.cnf.d/mariadb-server.cnf mysqld innodb_file_per_table on
crudini --set /etc/my.cnf.d/mariadb-server.cnf mysqld max_connections 4096
crudini --set /etc/my.cnf.d/mariadb-server.cnf mysqld collation-server utf8_general_ci
crudini --set /etc/my.cnf.d/mariadb-server.cnf mysqld character-set-server utf8
crudini --set /etc/my.cnf.d/mariadb-server.cnf mysqld user mysql

systemctl enable mariadb.service
systemctl restart mariadb.service
sleep 10

$EXPECT <<EOF
spawn mysql_secure_installation
expect "Enter current password for root (enter for none):" {
send "\r";exp_continue
} "Set root password?" {
send "y\r";exp_continue
} "New password:" {
send "$DB_PASS\r";exp_continue
} "Re-enter new password:" {
send "$DB_PASS\r";exp_continue
} "Remove anonymous users?" {
send "y\r";exp_continue
} "Disallow root login remotely?" {
send "n\r";exp_continue
} "Remove test database and access to it?" {
send "y\r";exp_continue
} "Reload privilege tables now?" {
send "y\r";exp_continue
} "*ERROR*" {
exit 1
}
EOF
echo -e "end.\n"

# rabbitmq
echo "start rabbitmq..."
systemctl enable rabbitmq-server.service
systemctl start rabbitmq-server.service
sleep 10
rabbitmqctl add_user openstack RABBIT_PASS
rabbitmqctl set_permissions openstack ".*" ".*" ".*"
echo -e "end.\n"

# memcached
echo "start memcached..."
sed -i "s/127.0.0.1/$LOCAL_C_IP/g" /etc/sysconfig/memcached
systemctl enable memcached.service
systemctl start memcached.service
echo -e "end.\n"

# keystone
echo "start keystone..."
mysql -uroot -p$DB_PASS -e "CREATE DATABASE keystone;"
mysql -uroot -p$DB_PASS -e "GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'localhost' IDENTIFIED BY 'KEYSTONE_DBPASS';"
mysql -uroot -p$DB_PASS -e "GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'%' IDENTIFIED BY 'KEYSTONE_DBPASS';"

crudini --set /etc/keystone/keystone.conf DEFAULT admin_token 7027356a188bc8247884
crudini --set /etc/keystone/keystone.conf database connection mysql://keystone:KEYSTONE_DBPASS@$LOCAL_C_IP/keystone
crudini --set /etc/keystone/keystone.conf memcache servers $LOCAL_C_IP:11211
crudini --set /etc/keystone/keystone.conf token provider keystone.token.providers.uuid.Provider
crudini --set /etc/keystone/keystone.conf token driver keystone.token.persistence.backends.memcache.Token
crudini --set /etc/keystone/keystone.conf revoke driver keystone.contrib.revoke.backends.sql.Revoke

su -s /bin/sh -c "keystone-manage db_sync" keystone

sed -i "s/^#ServerName.*/ServerName $LOCAL_C_IP:80/" /etc/httpd/conf/httpd.conf
\cp $CONF_PATH/keystone/wsgi-keystone.conf /etc/httpd/conf.d/
mkdir -p /var/www/cgi-bin/keystone
\cp $CONF_PATH/keystone/main /var/www/cgi-bin/keystone/
\cp $CONF_PATH/keystone/admin /var/www/cgi-bin/keystone/
chown -R keystone:keystone /var/www/cgi-bin/keystone
chmod 755 /var/www/cgi-bin/keystone/*
systemctl enable httpd.service
systemctl start httpd.service
sleep 20

export OS_TOKEN=7027356a188bc8247884
export OS_URL=http://$LOCAL_C_IP:35357/v2.0

openstack service create --name keystone --description "OpenStack Identity" identity
openstack endpoint create --publicurl http://$LOCAL_C_IP:5000/v2.0 --internalurl http://$LOCAL_C_IP:5000/v2.0 --adminurl http://$LOCAL_C_IP:35357/v2.0 --region RegionOne identity
openstack project create --description "Admin Project" admin
openstack user create --password $ADMIN_PASS admin
openstack role create admin
openstack role add --project admin --user admin admin
openstack project create --description "Service Project" service
openstack role create user

unset OS_TOKEN OS_URL

\cp $CONF_PATH/keystone/admin-openrc.sh /home/
sed -i "s/ADMIN_PASS/$ADMIN_PASS/g" /home/admin-openrc.sh
sed -i "s/CONTROLLER_VIP/$LOCAL_C_IP/g" /home/admin-openrc.sh
. /home/admin-openrc.sh
echo -e "end.\n"

# glance
echo  "start glance..."
mysql -uroot -p$DB_PASS -e "CREATE DATABASE glance;"
mysql -uroot -p$DB_PASS -e "GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'localhost' IDENTIFIED BY 'GLANCE_DBPASS';"
mysql -uroot -p$DB_PASS -e "GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'%' IDENTIFIED BY 'GLANCE_DBPASS';"

openstack user create --password GLANCE_PASS glance
openstack role add --project service --user glance admin
openstack service create --name glance --description "OpenStack Image service" image
openstack endpoint create --publicurl http://$LOCAL_C_IP:9292 --internalurl http://$LOCAL_C_IP:9292 --adminurl http://$LOCAL_C_IP:9292 --region RegionOne image

crudini --set /etc/glance/glance-api.conf database connection "mysql://glance:GLANCE_DBPASS@$LOCAL_C_IP/glance"
crudini --set /etc/glance/glance-api.conf keystone_authtoken auth_uri "http://$LOCAL_C_IP:5000"
crudini --set /etc/glance/glance-api.conf keystone_authtoken auth_url "http://$LOCAL_C_IP:35357"
crudini --set /etc/glance/glance-api.conf keystone_authtoken auth_plugin password
crudini --set /etc/glance/glance-api.conf keystone_authtoken project_domain_id default
crudini --set /etc/glance/glance-api.conf keystone_authtoken user_domain_id default
crudini --set /etc/glance/glance-api.conf keystone_authtoken project_name service
crudini --set /etc/glance/glance-api.conf keystone_authtoken username glance
crudini --set /etc/glance/glance-api.conf keystone_authtoken password GLANCE_PASS
crudini --set /etc/glance/glance-api.conf paste_deploy flavor keystone
crudini --set /etc/glance/glance-api.conf glance_store default_store file
crudini --set /etc/glance/glance-api.conf glance_store filesystem_store_datadir /var/lib/glance/images/

crudini --set /etc/glance/glance-registry.conf database connection "mysql://glance:GLANCE_DBPASS@$LOCAL_C_IP/glance"
crudini --set /etc/glance/glance-registry.conf keystone_authtoken auth_uri "http://$LOCAL_C_IP:5000"
crudini --set /etc/glance/glance-registry.conf keystone_authtoken auth_url "http://$LOCAL_C_IP:35357"
crudini --set /etc/glance/glance-registry.conf keystone_authtoken auth_plugin password
crudini --set /etc/glance/glance-registry.conf keystone_authtoken project_domain_id default
crudini --set /etc/glance/glance-registry.conf keystone_authtoken user_domain_id default
crudini --set /etc/glance/glance-registry.conf keystone_authtoken project_name service
crudini --set /etc/glance/glance-registry.conf keystone_authtoken username glance
crudini --set /etc/glance/glance-registry.conf keystone_authtoken password GLANCE_PASS
crudini --set /etc/glance/glance-registry.conf paste_deploy flavor keystone
crudini --set /etc/glance/glance-registry.conf DEFAULT notification_driver noop

su -s /bin/sh -c "glance-manage db_sync" glance

systemctl enable openstack-glance-api.service openstack-glance-registry.service
systemctl start openstack-glance-api.service openstack-glance-registry.service
echo -e "end.\n"

## nova
echo "start nova..."
mysql -uroot -p$DB_PASS -e "CREATE DATABASE nova;"
mysql -uroot -p$DB_PASS -e "GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'localhost' IDENTIFIED BY 'NOVA_DBPASS';"
mysql -uroot -p$DB_PASS -e "GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'%' IDENTIFIED BY 'NOVA_DBPASS';"

openstack user create --password NOVA_PASS nova
openstack role add --project service --user nova admin
openstack service create --name nova --description "OpenStack Compute" compute
openstack endpoint create --publicurl http://$LOCAL_C_IP:8774/v2/%\(tenant_id\)s --internalurl http://$LOCAL_C_IP:8774/v2/%\(tenant_id\)s --adminurl http://$LOCAL_C_IP:8774/v2/%\(tenant_id\)s --region RegionOne compute

crudini --set /etc/nova/nova.conf database connection "mysql://nova:NOVA_DBPASS@$LOCAL_C_IP/nova"
crudini --set /etc/nova/nova.conf DEFAULT rpc_backend rabbit
crudini --set /etc/nova/nova.conf oslo_messaging_rabbit rabbit_host $LOCAL_C_IP
crudini --set /etc/nova/nova.conf oslo_messaging_rabbit rabbit_userid openstack
crudini --set /etc/nova/nova.conf oslo_messaging_rabbit rabbit_password RABBIT_PASS
crudini --set /etc/nova/nova.conf DEFAULT auth_strategy keystone
crudini --set /etc/nova/nova.conf keystone_authtoken auth_uri "http://$LOCAL_C_IP:5000"
crudini --set /etc/nova/nova.conf keystone_authtoken auth_url "http://$LOCAL_C_IP:35357"
crudini --set /etc/nova/nova.conf keystone_authtoken auth_plugin password
crudini --set /etc/nova/nova.conf keystone_authtoken project_domain_id default
crudini --set /etc/nova/nova.conf keystone_authtoken user_domain_id default
crudini --set /etc/nova/nova.conf keystone_authtoken project_name service
crudini --set /etc/nova/nova.conf keystone_authtoken username nova
crudini --set /etc/nova/nova.conf keystone_authtoken password NOVA_PASS
crudini --set /etc/nova/nova.conf DEFAULT my_ip $LOCAL_C_IP
crudini --set /etc/nova/nova.conf DEFAULT vnc_enabled false
crudini --set /etc/nova/nova.conf DEFAULT web /usr/share/spice-html5
crudini --set /etc/nova/nova.conf spice html5proxy_host $LOCAL_C_IP
crudini --set /etc/nova/nova.conf spice html5proxy_port 6082
crudini --set /etc/nova/nova.conf spice html5proxy_base_url http://$LOCAL_C_IP:6082/spice_auto.html
crudini --set /etc/nova/nova.conf spice enabled true
crudini --set /etc/nova/nova.conf spice agent_enabled true
crudini --set /etc/nova/nova.conf spice keymap en-us
crudini --set /etc/nova/nova.conf glance host $LOCAL_C_IP
crudini --set /etc/nova/nova.conf oslo_concurrency lock_path /var/lib/nova/tmp

su -s /bin/sh -c "nova-manage db sync" nova

systemctl enable openstack-nova-api.service openstack-nova-cert.service openstack-nova-consoleauth.service openstack-nova-scheduler.service openstack-nova-conductor.service openstack-nova-spicehtml5proxy.service
systemctl start openstack-nova-api.service openstack-nova-cert.service openstack-nova-consoleauth.service openstack-nova-scheduler.service openstack-nova-conductor.service openstack-nova-spicehtml5proxy.service
echo -e "end.\n"

# neutron
echo "start neutron..."
mysql -uroot -p$DB_PASS -e "CREATE DATABASE neutron;"
mysql -uroot -p$DB_PASS -e "GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'localhost' IDENTIFIED BY 'NEUTRON_DBPASS';"
mysql -uroot -p$DB_PASS -e "GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'%' IDENTIFIED BY 'NEUTRON_DBPASS';"

openstack user create --password NEUTRON_PASS neutron
openstack role add --project service --user neutron admin
openstack service create --name neutron --description "OpenStack Networking" network
openstack endpoint create --publicurl http://$LOCAL_C_IP:9696 --adminurl http://$LOCAL_C_IP:9696 --internalurl http://$LOCAL_C_IP:9696 --region RegionOne network

crudini --set /etc/neutron/neutron.conf database connection "mysql://neutron:NEUTRON_DBPASS@$LOCAL_C_IP/neutron"
crudini --set /etc/neutron/neutron.conf DEFAULT rpc_backend rabbit
crudini --set /etc/neutron/neutron.conf oslo_messaging_rabbit rabbit_host $LOCAL_C_IP
crudini --set /etc/neutron/neutron.conf oslo_messaging_rabbit rabbit_userid openstack
crudini --set /etc/neutron/neutron.conf oslo_messaging_rabbit rabbit_password RABBIT_PASS
crudini --set /etc/neutron/neutron.conf DEFAULT auth_strategy keystone
crudini --set /etc/neutron/neutron.conf keystone_authtoken auth_uri "http://$LOCAL_C_IP:5000"
crudini --set /etc/neutron/neutron.conf keystone_authtoken auth_url "http://$LOCAL_C_IP:35357"
crudini --set /etc/neutron/neutron.conf keystone_authtoken auth_plugin password
crudini --set /etc/neutron/neutron.conf keystone_authtoken project_domain_id default
crudini --set /etc/neutron/neutron.conf keystone_authtoken user_domain_id default
crudini --set /etc/neutron/neutron.conf keystone_authtoken project_name service
crudini --set /etc/neutron/neutron.conf keystone_authtoken username neutron
crudini --set /etc/neutron/neutron.conf keystone_authtoken password NEUTRON_PASS
crudini --set /etc/neutron/neutron.conf DEFAULT core_plugin ml2
crudini --set /etc/neutron/neutron.conf DEFAULT service_plugins router
crudini --set /etc/neutron/neutron.conf DEFAULT allow_overlapping_ips True
crudini --set /etc/neutron/neutron.conf DEFAULT notify_nova_on_port_status_changes True
crudini --set /etc/neutron/neutron.conf DEFAULT notify_nova_on_port_data_changes True
crudini --set /etc/neutron/neutron.conf DEFAULT nova_url "http://$LOCAL_C_IP:8774/v2"
crudini --set /etc/neutron/neutron.conf nova auth_url "http://$LOCAL_C_IP:35357"
crudini --set /etc/neutron/neutron.conf nova auth_plugin password
crudini --set /etc/neutron/neutron.conf nova project_domain_id default
crudini --set /etc/neutron/neutron.conf nova user_domain_id default
crudini --set /etc/neutron/neutron.conf nova region_name RegionOne
crudini --set /etc/neutron/neutron.conf nova project_name service
crudini --set /etc/neutron/neutron.conf nova username nova
crudini --set /etc/neutron/neutron.conf nova password NOVA_PASS

crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 type_drivers "flat,vxlan"
crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 tenant_network_types vxlan
crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 mechanism_drivers openvswitch
crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2_type_flat flat_networks "external,external1"
crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2_type_vxlan vni_ranges 1:1000
crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini securitygroup enable_security_group True
crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini securitygroup enable_ipset True
crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini securitygroup firewall_driver neutron.agent.linux.iptables_firewall.OVSHybridIptablesFirewallDriver
crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ovs local_ip $LOCAL_T_IP
crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ovs bridge_mappings "external:br-ex,external1:br-ex1"
crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ovs integration_bridge br-int
crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ovs tunnel_bridge br-tun
crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini agent tunnel_types vxlan

crudini --set /etc/neutron/l3_agent.ini DEFAULT interface_driver neutron.agent.linux.interface.OVSInterfaceDriver
crudini --set /etc/neutron/l3_agent.ini DEFAULT external_network_bridge
crudini --set /etc/neutron/l3_agent.ini DEFAULT router_delete_namespaces True

crudini --set /etc/neutron/dhcp_agent.ini DEFAULT interface_driver neutron.agent.linux.interface.OVSInterfaceDriver
crudini --set /etc/neutron/dhcp_agent.ini DEFAULT dhcp_driver neutron.agent.linux.dhcp.Dnsmasq
crudini --set /etc/neutron/dhcp_agent.ini DEFAULT dnsmasq_config_file /etc/neutron/dnsmasq-neutron.conf
crudini --set /etc/neutron/dhcp_agent.ini DEFAULT dnsmasq_dns_servers 114.114.114.114
crudini --set /etc/neutron/dhcp_agent.ini DEFAULT dhcp_delete_namespaces True

\cp $CONF_PATH/neutron/dnsmasq-neutron.conf /etc/neutron/dnsmasq-neutron.conf

crudini --set /etc/neutron/metadata_agent.ini DEFAULT auth_uri "http://$LOCAL_C_IP:5000"
crudini --set /etc/neutron/metadata_agent.ini DEFAULT auth_url "http://$LOCAL_C_IP:35357"
crudini --set /etc/neutron/metadata_agent.ini DEFAULT auth_region RegionOne
crudini --set /etc/neutron/metadata_agent.ini DEFAULT auth_plugin password
crudini --set /etc/neutron/metadata_agent.ini DEFAULT project_domain_id default
crudini --set /etc/neutron/metadata_agent.ini DEFAULT user_domain_id default
crudini --set /etc/neutron/metadata_agent.ini DEFAULT project_name service
crudini --set /etc/neutron/metadata_agent.ini DEFAULT username neutron
crudini --set /etc/neutron/metadata_agent.ini DEFAULT password NEUTRON_PASS
crudini --set /etc/neutron/metadata_agent.ini DEFAULT nova_metadata_ip $LOCAL_C_IP
crudini --set /etc/neutron/metadata_agent.ini DEFAULT metadata_proxy_shared_secret METADATA_SECRET

crudini --set /etc/nova/nova.conf DEFAULT network_api_class nova.network.neutronv2.api.API
crudini --set /etc/nova/nova.conf DEFAULT security_group_api neutron
crudini --set /etc/nova/nova.conf DEFAULT linuxnet_interface_driver nova.network.linux_net.LinuxOVSInterfaceDriver
crudini --set /etc/nova/nova.conf DEFAULT firewall_driver nova.virt.firewall.NoopFirewallDriver
crudini --set /etc/nova/nova.conf neutron url "http://$LOCAL_C_IP:9696"
crudini --set /etc/nova/nova.conf neutron auth_strategy keystone
crudini --set /etc/nova/nova.conf neutron admin_auth_url "http://$LOCAL_C_IP:35357/v2.0"
crudini --set /etc/nova/nova.conf neutron admin_tenant_name service
crudini --set /etc/nova/nova.conf neutron admin_username neutron
crudini --set /etc/nova/nova.conf neutron admin_password NEUTRON_PASS
crudini --set /etc/nova/nova.conf neutron service_metadata_proxy True
crudini --set /etc/nova/nova.conf neutron metadata_proxy_shared_secret METADATA_SECRET

ln -s /etc/neutron/plugins/ml2/ml2_conf.ini /etc/neutron/plugin.ini
su -s /bin/sh -c "neutron-db-manage --config-file /etc/neutron/neutron.conf --config-file /etc/neutron/plugins/ml2/ml2_conf.ini upgrade head" neutron

pkill dnsmasq

systemctl enable openvswitch.service
systemctl start openvswitch.service

ovs-vsctl add-br br-ex 
ovs-vsctl add-br br-ex1
if [ -n "$LOCAL_E_INTERFACE" ]; then
    ovs-vsctl add-port br-ex $LOCAL_E_INTERFACE
fi

\cp /usr/lib/systemd/system/neutron-openvswitch-agent.service /usr/lib/systemd/system/neutron-openvswitch-agent.service.orig
sed -i 's,plugins/openvswitch/ovs_neutron_plugin.ini,plugin.ini,g' /usr/lib/systemd/system/neutron-openvswitch-agent.service

systemctl restart openstack-nova-api.service
systemctl enable neutron-server.service neutron-openvswitch-agent.service neutron-dhcp-agent.service neutron-metadata-agent.service neutron-l3-agent.service
systemctl start neutron-server.service neutron-openvswitch-agent.service neutron-dhcp-agent.service neutron-metadata-agent.service neutron-l3-agent.service
echo -e "end.\n"

neutron net-create ext-net --router:external --provider:physical_network external --provider:network_type flat
sleep 3
neutron net-create ext-net1 --router:external --provider:physical_network external1 --provider:network_type flat

# dashboard
echo "start dashboard..."
\cp $CONF_PATH/dashboard/local_settings /etc/openstack-dashboard/local_settings
sed -i "s/^OPENSTACK_HOST.*/OPENSTACK_HOST = \"$LOCAL_C_IP\"/" /etc/openstack-dashboard/local_settings
DASH_INSTALL_PATH=/usr/share/openstack-dashboard/openstack_dashboard
\cp $CODE_PATH/openstack_dashboard/static/dashboard/img/* $DASH_INSTALL_PATH/static/dashboard/img/
setsebool -P httpd_can_network_connect on
chown -R apache:apache /usr/share/openstack-dashboard/static
systemctl enable httpd.service memcached.service
systemctl restart httpd.service memcached.service
echo -e "end.\n"

# cinder
echo "start cinder..."
mysql -uroot -p$DB_PASS -e "CREATE DATABASE cinder;"
mysql -uroot -p$DB_PASS -e "GRANT ALL PRIVILEGES ON cinder.* TO 'cinder'@'localhost' IDENTIFIED BY 'CINDER_DBPASS';"
mysql -uroot -p$DB_PASS -e "GRANT ALL PRIVILEGES ON cinder.* TO 'cinder'@'%' IDENTIFIED BY 'CINDER_DBPASS';"

openstack user create --password CINDER_PASS cinder
openstack role add --project service --user cinder admin
openstack service create --name cinder --description "OpenStack Block Storage" volume
openstack service create --name cinderv2 --description "OpenStack Block Storage" volumev2
openstack endpoint create --publicurl http://$LOCAL_C_IP:8776/v2/%\(tenant_id\)s --internalurl http://$LOCAL_C_IP:8776/v2/%\(tenant_id\)s --adminurl http://$LOCAL_C_IP:8776/v2/%\(tenant_id\)s --region RegionOne volume
openstack endpoint create --publicurl http://$LOCAL_C_IP:8776/v2/%\(tenant_id\)s --internalurl http://$LOCAL_C_IP:8776/v2/%\(tenant_id\)s --adminurl http://$LOCAL_C_IP:8776/v2/%\(tenant_id\)s --region RegionOne volumev2

\cp /usr/share/cinder/cinder-dist.conf /etc/cinder/cinder.conf
chown -R cinder:cinder /etc/cinder/cinder.conf

crudini --set /etc/cinder/cinder.conf database connection mysql://cinder:CINDER_DBPASS@$LOCAL_C_IP/cinder
crudini --set /etc/cinder/cinder.conf DEFAULT rpc_backend rabbit
crudini --set /etc/cinder/cinder.conf oslo_messaging_rabbit rabbit_host $LOCAL_C_IP
crudini --set /etc/cinder/cinder.conf oslo_messaging_rabbit rabbit_userid openstack
crudini --set /etc/cinder/cinder.conf oslo_messaging_rabbit rabbit_password RABBIT_PASS
crudini --set /etc/cinder/cinder.conf DEFAULT auth_strategy keystone
crudini --set /etc/cinder/cinder.conf keystone_authtoken auth_uri http://$LOCAL_C_IP:5000
crudini --set /etc/cinder/cinder.conf keystone_authtoken auth_url http://$LOCAL_C_IP:35357
crudini --set /etc/cinder/cinder.conf keystone_authtoken auth_plugin password
crudini --set /etc/cinder/cinder.conf keystone_authtoken project_domain_id default
crudini --set /etc/cinder/cinder.conf keystone_authtoken user_domain_id default
crudini --set /etc/cinder/cinder.conf keystone_authtoken project_name service
crudini --set /etc/cinder/cinder.conf keystone_authtoken username cinder
crudini --set /etc/cinder/cinder.conf keystone_authtoken password CINDER_PASS
crudini --set /etc/cinder/cinder.conf DEFAULT my_ip $LOCAL_C_IP
crudini --set /etc/cinder/cinder.conf oslo_concurrency lock_path /var/lock/cinder

su -s /bin/sh -c "cinder-manage db sync" cinder

#todo finish cinder config
systemctl enable openstack-cinder-api.service
systemctl start openstack-cinder-api.service

echo "Done."

