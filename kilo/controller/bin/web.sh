#!/bin/bash
## get installation package absolute path
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
GLANCE_PATH="$INSTALL_PACKAGE_PATH/confs/glance"
###iso path
IMAGE_PATH="/tmp/image"
#ext_net_bc="172.16.0.0/16"
#ext_net_bc_start="172.16.99.2"
#ext_net_bc_end="172.16.99.254"
#ext_net_bc_gateway="172.16.1.1"

#ext_net1_bc="192.168.99.0/24"
#ext_net1_bc_start="192.168.99.2"
#ext_net1_bc_end="192.168.99.254"
#ext_net1_bc_gateway="192.99.100.1"

#local_net0_bc="192.168.100.0/24"
#local_net0_bc_start="192.168.100.2"
#local_net0_bc_end="192.168.100.254"
#local_net0_bc_gateway="192.100.200.1"

#local_net1_bc="192.168.200.0/24"
#local_net1_bc_start="192.168.200.2"
#local_net1_bc_end="192.168.200.254"
#local_net1_bc_gateway="192.168.200.1"



source /home/admin-openrc.sh


# crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ovs bridge_mappings "external:br-ex,external1:br-ex1"
# crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2_type_flat flat_networks "external,external1"
# systemctl start neutron-server.service neutron-openvswitch-agent.service neutron-dhcp-agent.service neutron-metadata-agent.service neutron-l3-agent.service
# neutron net-create ext-net1 --router:external --provider:physical_network external1 --provider:network_type flat

###create network and route
#neutron subnet-create ext-net $ext_net_bc --name ext-subnet --allocation-pool start=$ext_net_bc_start,end=$ext_net_bc_end  --disable-dhcp --gateway $ext_net_bc_gateway
#neutron subnet-create ext-net1 $ext_net1_bc --name ext-subnet1 --allocation-pool start=$ext_net1_bc_start,end=$ext_net1_bc_end  --disable-dhcp --gateway $ext_net1_bc_gateway

#neutron net-create local-net0 
#neutron subnet-create local-net0 $local_net0_bc --name local-subnet0 --allocation-pool start=$local_net0_bc_start,end=$local_net0_bc_end  --disable-dhcp --gateway $local_net0_bc_gateway

#neutron net-create local-net1 
#neutron subnet-create local-net1 $local_net1_bc --name local-subnet1 --allocation-pool start=$local_net1_bc_start,end=$local_net1_bc_end  --disable-dhcp --gateway $local_net1_bc_gateway

#neutron net-list

#neutron router-create router
#neutron router-gateway-set router ext-net
#neutron router-interface-add router $local-subnet0

#neutron router-create router1
#neutron router-gateway-set router ext-net1
#neutron router-interface-add router1 $local-subnet1



###Upload the image
fname(){
    image_file="$IMAGE_PATH/$num2"
    if [ ! -f "$image_file" ]; then
        echo "未发现$num2镜像"
        #exit 1
    fi
    detect=`glance image-list | grep $num1 | awk '{print $2}'`
    if [ "$detect" = "$num1" ]; then
        echo "已创建$num1镜像"          
    else
        glance image-create --name "$num2" --file $image_file --id $num1 --disk-format qcow2 --container-format bare --visibility public --progress
    fi
    #glance image-create --name "$num2" --file $image_file --id $num1 --disk-format qcow2 --container-format bare --visibility public --progress
    #echo "glance image-create --name \"$num2\" --file $num2 --id $num1 --disk-format qcow2 --container-format bare --visibility public --progress"
}

While_read_LINE(){
file="$GLANCE_PATH/create_glance.txt"
while read line
do
   num1=`echo $line | awk '{print $1}'`
   num2=`echo $line | awk '{print $2}'`
   fname $num1 $num2
done < $file
}

While_read_LINE


###Start cloud host
# local_net_bc_id=`neutron net-list | grep local-net0 | awk '{print $2}'`
# local_net1_bc_id=`neutron net-list | grep local-net1 | awk '{print $2}'`

# nova boot --flavor 2 \
# --image 280816ff-4900-4e77-ada3-f7bccbb6d703  \
# --nic net-id="$local_net_bc_id",v4-fixed-ip=192.168.100.4 \
# --nic net-id="$local_net1_bc_id",v4-fixed-ip=192.168.200.4 \
# --security_group default seep_web_server

# neutron floatingip-create ext-net
# neutron floatingip-create ext-net1
# floating_ip_bc=`neutron floatingip-list | grep 172 |awk '{print $5}'`
# floating_ip1_bc=`neutron floatingip-list | grep 192 |awk '{print $5}'`
# port_id_bc=`neutron port-list | grep 192.168.100.4 | awk '{print $2}'`
# port_id1_bc=`neutron port-list | grep 192.168.200.4 | awk '{print $2}'`
# neutron floatingip-create --port-id $port_id_bc $floating_ip_bc
# neutron floatingip-create --port-id $port_id1_bc $floating_ip1_bc
# 
# ### rm -rf /etc/udev/rules.d/70-persistent-net.rules
# ### reboot
# 
# openStackHost=`ifconfig eth0 | grep -w inet | awk '{print $2}'`
# flavorRef=`nova flavor-list | grep m1.small | awk '{print $2}'`
# extNetId=`neutron net-list | grep ext-net1 | awk '{print $2}'`
# floating_ip_bc=`neutron floatingip-list | grep 172 |awk '{print $5}'`
# cat 
# cat >> INSTALL_PACKAGE_PATH/confs/web.conf <<EOF       
# [openstack]
# Host=$openStackHost
# flavor=$flavorRef
# extNet=$extNetId

# [web]
# floating_ip=$floating_ip_bc
# EOF

###route
# rm -rf /etc/udev/rules.d/70-persistent-net.rules
# echo "any net 192.168.99.0 netmask 255.255.255.0 gw 192.168.200.1 dev eth1" >> /etc/sysconfig/static-routes
# sed -i "s/^DEFROUTE=.*/DEFROUTE=no/" /etc/sysconfig/network-scripts/ifcfg-eth1
# vim /var/lib/tomcat6/webapps/seep/WEB-INF/classes/sysset.properties
# openStackHost=`ifconfig eth0 | grep -w inet | awk '{print $2}'`
# flavorRef=`nova flavor-list | grep m1.small | awk '{print $2}'`
# extNetId=`neutron net-list | grep ext-net1 | awk '{print $2}'`
# webAddr=172.16.5.80:8080(web服务器的浮动ip)
# weburl:172.16.5.80:8080/seep
# 
# SET FOREIGN_KEY_CHECKS=0;
# SELECT @@FOREIGN_KEY_CHECKS;
# delete from images where id="667a09da-e79e-4381-a341-39a1a90a9b63";
# delete from image_locations where id="667a09da-e79e-4381-a341-39a1a90a9b63";
