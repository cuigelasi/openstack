#!/bin/bash

### function ###

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
    echo $this_dir
}

## modify nic conf
## param interface ip prefix
## return null
modifyNicConf()
{
    local interface=$1
    local ipaddr=$2
    local prefix=$3
    grep -Pq "^IPADDR\d*=$ipaddr" /etc/sysconfig/network-scripts/ifcfg-$interface
    if [ $? -eq 0 ]; then
        return
    fi
    grep -q "BOOTPROTO=none" /etc/sysconfig/network-scripts/ifcfg-$interface
    if [ $? -ne 0 ]; then
        sed -i "/BOOTPROTO/d" /etc/sysconfig/network-scripts/ifcfg-$interface
        echo "BOOTPROTO=none" >> /etc/sysconfig/network-scripts/ifcfg-$interface
        sed -i "/ONBOOT/d" /etc/sysconfig/network-scripts/ifcfg-$interface
	echo "ONBOOT=yes" >> /etc/sysconfig/network-scripts/ifcfg-$interface
	echo "IPADDR=$ipaddr" >> /etc/sysconfig/network-scripts/ifcfg-$interface
	echo "PREFIX=$prefix" >> /etc/sysconfig/network-scripts/ifcfg-$interface
    else
	num=`grep "^IPADDR" /etc/sysconfig/network-scripts/ifcfg-$interface | wc -l`
	echo "IPADDR$num=$ipaddr" >> /etc/sysconfig/network-scripts/ifcfg-$interface
	echo "PREFIX$num=$prefix" >> /etc/sysconfig/network-scripts/ifcfg-$interface
    fi
}
#Comparing the MAC address
macThan()
{
    mac1=`echo $1 | tr '[:lower:]' '[:upper:]'`
    mac2=`echo $2 | tr '[:lower:]' '[:upper:]'`
    if [ "$mac1" == "$mac2" ]; then
        echo true
    else
        echo false
    fi
}
### script start ###

INIT_PATH=`getPath`

declare -a nics
declare -a macs
declare -a ipaddrs
declare -a bandwidths

conf_controller_mac=""
conf_controller_ip=""
conf_tunnel_mac=""
conf_tunnel_ip=""
conf_storage_mac=""
conf_storage_ip=""
conf_hostname=""
conf_role=""
conf_ext_mac=""


## prepare yum local repo
yum -y install crudini

## read config
deploy_ip=`crudini --get $INIT_PATH/auto-config kickstart ipaddr`
admin_password=`crudini --get $INIT_PATH/auto-config openstack admin_password`
mysql_password=`crudini --get $INIT_PATH/auto-config openstack mysql_password`
pcs_password=`crudini --get $INIT_PATH/auto-config pcs pcs_password`
dvr=`crudini --get $INIT_PATH/auto-config openstack dvr`
controller_vip=`crudini --get $INIT_PATH/auto-config openstack controller_vip`
major_hostname=`crudini --get $INIT_PATH/auto-config pcs major_hostname`
major_ip=`crudini --get $INIT_PATH/auto-config pcs major_ip`
standby_hostname=`crudini --get $INIT_PATH/auto-config pcs standby_hostname`
standby_ip=`crudini --get $INIT_PATH/auto-config pcs standby_ip`
openstack_controller_network=`crudini --get $INIT_PATH/auto-config network openstack_controller_network`
openstack_tunnel_network=`crudini --get $INIT_PATH/auto-config network openstack_tunnel_network`
openstack_storage_network=`crudini --get $INIT_PATH/auto-config network openstack_storage_network`

## nic
nicstr=`ifconfig | grep 1500 | awk -F : '{print $1}'`
nics=(${nicstr})
len=${#nics[@]}
for ((i=0;i<$len;i++))
do
    nic=${nics[$i]}
	mac=`ifconfig $nic | grep ether | awk '{print $2}'`
	ipaddr=`ifconfig $nic | grep -w inet | awk '{print $2}'`
	bandwidth=`ethtool $nic | grep Speed | grep -oP '\d+'`
	macs[$i]=$mac
	ipaddrs[$i]=$ipaddr
	bandwidths[$i]=$bandwidth
done

ext_interface=""
flag=false
node_num=`sed -n "/^\[node.*\]/p" $INIT_PATH/auto-config | wc -l`
for ((i=0;i<$node_num;i++))
do
    section="node$[i+1]"	
    conf_controller_mac=`crudini --get $INIT_PATH/auto-config $section controller_mac`
    conf_controller_ip=`crudini --get $INIT_PATH/auto-config $section controller_ip`
    conf_tunnel_mac=`crudini --get $INIT_PATH/auto-config $section tunnel_mac`
    conf_tunnel_ip=`crudini --get $INIT_PATH/auto-config $section tunnel_ip`
    conf_storage_mac=`crudini --get $INIT_PATH/auto-config $section storage_mac`
    conf_storage_ip=`crudini --get $INIT_PATH/auto-config $section storage_ip`
    conf_hostname=`crudini --get $INIT_PATH/auto-config $section hostname`
    conf_role=`crudini --get $INIT_PATH/auto-config $section role`
    conf_ext_mac=`crudini --get $INIT_PATH/auto-config $section ext_mac`
    len=${#nics[@]}
    for ((j=0;j<$len;j++))
    do
        controller_than=`macThan $conf_controller_mac ${macs[$j]} ` 
        tunnel_than=`macThan $conf_tunnel_mac ${macs[$j]} `
        storage_than=`macThan $conf_storage_mac ${macs[$j]} `
        ext_than=`macThan $conf_ext_mac ${macs[$j]} `       
        if "$controller_than"; then
            flag=true
            modifyNicConf ${nics[$j]} $conf_controller_ip ${openstack_controller_network##*/}
        fi
        if "$tunnel_than"; then
            modifyNicConf ${nics[$j]} $conf_tunnel_ip ${openstack_tunnel_network##*/}
        fi
        if "$storage_than"; then
            modifyNicConf ${nics[$j]} $conf_storage_ip ${openstack_storage_network##*/}
        fi
        if "$ext_than"; then
            ext_interface=${nics[$j]}
            sed -i "/BOOTPROTO/d" /etc/sysconfig/network-scripts/ifcfg-${nics[$j]}
            echo "BOOTPROTO=none" >> /etc/sysconfig/network-scripts/ifcfg-${nics[$j]}
            sed -i "/ONBOOT/d" /etc/sysconfig/network-scripts/ifcfg-${nics[$j]}
            echo "ONBOOT=yes" >> /etc/sysconfig/network-scripts/ifcfg-${nics[$j]}
        fi
    done
	if $flag ; then
	    break
	fi	
done

for ((i=0;i<$node_num;i++))
do
    section="node$[i+1]"
    name=`crudini --get $INIT_PATH/auto-config $section hostname`
    ip=`crudini --get $INIT_PATH/auto-config $section controller_ip`
    echo "$ip    $name" >> /etc/hosts
done

echo "$conf_hostname" > /etc/hostname
