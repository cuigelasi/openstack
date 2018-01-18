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
YUM_PATH=$INSTALL_PACKAGE_PATH/local_yum

# hostname
HOSTNAME=compute
# local controller ip
LOCAL_C_IP=172.16.5.138
# local tunnel ip
LOCAL_T_IP=192.168.5.138
# local external interface
LOCAL_E_INTERFACE=eth1
# major ip
MAJOR_IP=172.16.5.137
# Verify
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
    exit 1
fi
if  [ ! -n "$MAJOR_IP" ] ;then
    echo "Inform: Variable MAJOR_IP is set to default for empty"
    exit 1
fi


## install package
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
yum clean all
yum -y update
yum -y install expect crudini
yum -y install python-openstackclient openstack-selinux
yum -y install openstack-nova-compute sysfsutils spice-html5
yum -y install openstack-neutron openstack-neutron-ml2 openstack-neutron-openvswitch
yum -y install qemu lvm2
yum -y install openstack-cinder targetcli python-oslo-db python-oslo-log MySQL-python


# disable selinux
echo "disable selinux..."
setenforce 0
sed -i "s/^SELINUX=.*/SELINUX=disabled/" /etc/selinux/config
echo -e "end.\n"

## enable ports 
## spice:5900-5999/tcp  openvswitch:4789/udp
echo "enable firewall ports..."
firewall-cmd --zone=public --add-port=5900-5999/tcp --add-port=4789/udp --permanent
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
echo "server $MAJOR_IP iburst" >> /etc/chrony.conf
systemctl enable chronyd.service
systemctl restart chronyd.service
echo -e "end.\n"

# sysctl
echo "config sysctl..."
echo "net.ipv4.conf.all.rp_filter = 0" >> /etc/sysctl.conf
echo "net.ipv4.conf.default.rp_filter = 0" >> /etc/sysctl.conf
sysctl -p
echo -e "end.\n"

# nova
echo "start nova..."
crudini --set /etc/nova/nova.conf DEFAULT rpc_backend rabbit
crudini --set /etc/nova/nova.conf oslo_messaging_rabbit rabbit_host $MAJOR_IP
crudini --set /etc/nova/nova.conf oslo_messaging_rabbit rabbit_userid openstack
crudini --set /etc/nova/nova.conf oslo_messaging_rabbit rabbit_password RABBIT_PASS
crudini --set /etc/nova/nova.conf DEFAULT auth_strategy keystone
crudini --set /etc/nova/nova.conf keystone_authtoken auth_uri "http://$MAJOR_IP:5000"
crudini --set /etc/nova/nova.conf keystone_authtoken auth_url "http://$MAJOR_IP:35357"
crudini --set /etc/nova/nova.conf keystone_authtoken auth_plugin password
crudini --set /etc/nova/nova.conf keystone_authtoken project_domain_id default
crudini --set /etc/nova/nova.conf keystone_authtoken user_domain_id default
crudini --set /etc/nova/nova.conf keystone_authtoken project_name service
crudini --set /etc/nova/nova.conf keystone_authtoken username nova
crudini --set /etc/nova/nova.conf keystone_authtoken password NOVA_PASS
crudini --set /etc/nova/nova.conf DEFAULT my_ip $LOCAL_C_IP
crudini --set /etc/nova/nova.conf DEFAULT vnc_enabled false
crudini --set /etc/nova/nova.conf DEFAULT web /usr/share/spice-html5
crudini --set /etc/nova/nova.conf spice html5proxy_base_url "http://$MAJOR_IP:6082/spice_auto.html"
crudini --set /etc/nova/nova.conf spice server_listen 0.0.0.0
crudini --set /etc/nova/nova.conf spice server_proxyclient_address $LOCAL_C_IP
crudini --set /etc/nova/nova.conf spice enabled true
crudini --set /etc/nova/nova.conf spice agent_enabled False
crudini --set /etc/nova/nova.conf spice keymap en-us
crudini --set /etc/nova/nova.conf glance host $MAJOR_IP
crudini --set /etc/nova/nova.conf oslo_concurrency lock_path /var/lib/nova/tmp
crudini --set /etc/nova/nova.conf libvirt virt_type kvm
crudini --set /etc/nova/nova.conf libvirt use_usb_tablet true
crudini --set /etc/nova/nova.conf DEFAULT resume_guests_state_on_host_boot true
crudini --set /etc/nova/nova.conf DEFAULT ram_allocation_ratio 1
crudini --set /etc/nova/nova.conf DEFAULT cpu_allocation_ratio 1

systemctl enable libvirtd.service openstack-nova-compute.service
systemctl start libvirtd.service openstack-nova-compute.service
echo -e "end.\n"

# neutron
echo "start neutron..."
crudini --set /etc/neutron/neutron.conf DEFAULT rpc_backend rabbit
crudini --set /etc/neutron/neutron.conf oslo_messaging_rabbit rabbit_host $MAJOR_IP
crudini --set /etc/neutron/neutron.conf oslo_messaging_rabbit rabbit_userid openstack
crudini --set /etc/neutron/neutron.conf oslo_messaging_rabbit rabbit_password RABBIT_PASS
crudini --set /etc/neutron/neutron.conf DEFAULT auth_strategy keystone
crudini --set /etc/neutron/neutron.conf keystone_authtoken auth_uri "http://$MAJOR_IP:5000"
crudini --set /etc/neutron/neutron.conf keystone_authtoken auth_url "http://$MAJOR_IP:35357"
crudini --set /etc/neutron/neutron.conf keystone_authtoken auth_plugin password
crudini --set /etc/neutron/neutron.conf keystone_authtoken project_domain_id Default
crudini --set /etc/neutron/neutron.conf keystone_authtoken user_domain_id Default
crudini --set /etc/neutron/neutron.conf keystone_authtoken project_name service
crudini --set /etc/neutron/neutron.conf keystone_authtoken username neutron
crudini --set /etc/neutron/neutron.conf keystone_authtoken password NEUTRON_PASS
crudini --set /etc/neutron/neutron.conf DEFAULT core_plugin ml2
crudini --set /etc/neutron/neutron.conf DEFAULT service_plugins router
crudini --set /etc/neutron/neutron.conf DEFAULT allow_overlapping_ips True

crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 type_drivers "flat,vxlan"
crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 tenant_network_types vxlan
crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 mechanism_drivers openvswitch
crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2_type_vxlan vni_ranges "1:1000"
crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini securitygroup enable_security_group True
crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini securitygroup enable_ipset True
crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini securitygroup firewall_driver neutron.agent.linux.iptables_firewall.OVSHybridIptablesFirewallDriver
crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ovs local_ip $LOCAL_T_IP
crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini agent tunnel_types vxlan

crudini --set /etc/nova/nova.conf DEFAULT network_api_class nova.network.neutronv2.api.API
crudini --set /etc/nova/nova.conf DEFAULT security_group_api neutron
crudini --set /etc/nova/nova.conf DEFAULT linuxnet_interface_driver nova.network.linux_net.LinuxOVSInterfaceDriver
crudini --set /etc/nova/nova.conf DEFAULT firewall_driver nova.virt.firewall.NoopFirewallDriver
crudini --set /etc/nova/nova.conf neutron url "http://$MAJOR_IP:9696"
crudini --set /etc/nova/nova.conf neutron auth_strategy keystone
crudini --set /etc/nova/nova.conf neutron admin_auth_url "http://$MAJOR_IP:35357/v2.0"
crudini --set /etc/nova/nova.conf neutron admin_tenant_name service
crudini --set /etc/nova/nova.conf neutron admin_username neutron
crudini --set /etc/nova/nova.conf neutron admin_password NEUTRON_PASS

ln -s /etc/neutron/plugins/ml2/ml2_conf.ini /etc/neutron/plugin.ini

systemctl enable openvswitch.service
systemctl start openvswitch.service
#ovs-vsctl add-br br-ex

\cp /usr/lib/systemd/system/neutron-openvswitch-agent.service /usr/lib/systemd/system/neutron-openvswitch-agent.service.orig
sed -i 's,plugins/openvswitch/ovs_neutron_plugin.ini,plugin.ini,g' /usr/lib/systemd/system/neutron-openvswitch-agent.service

systemctl restart openstack-nova-compute.service
systemctl enable neutron-openvswitch-agent.service
systemctl start neutron-openvswitch-agent.service
echo -e "end.\n"

echo "Done."
