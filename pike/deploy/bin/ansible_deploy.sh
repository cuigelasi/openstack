#!/bin/bash
### function ###
##Quit the entire script
exit_script(){
    exit 1
}
##

## get installation package absolute path
getPath(){
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


## usage
usage()
{
    cat<<EOF

Usage: sh $0 [OPTION]

optional arguments:
    --check           check ansible
    --install         install ansible
e.g:
    sh $0 --check

EOF
}


## check ansible
check_ansible()
{
    echo "check_ansible..."
    ansible all -m ping
    echo "done"
}

## install ansible
install_ansible()
{
    echo "install_ansible..."
    yum -y install ansible
    yum -y install crudini
    DEPLOY_PATH=`getPath`
    echo $DEPLOY_PATH
    CONFIG_PATH="$DEPLOY_PATH/conf"
    echo $CONFIG_PATH
    sed -i '/## green/i\[pike] \n[pike_controller] \n[pike_compute]' /etc/ansible/hosts
    node_num=`sed -n "/^\[node.*\]/p" $CONFIG_PATH/auto-config | wc -l`
    for ((i=0;i<$node_num;i++))
    do
        section="node$[i+1]"
        conf_controller_role=`crudini --get $CONFIG_PATH/auto-config $section role`
        conf_controller_ip=`crudini --get $CONFIG_PATH/auto-config $section controller_ip`
        sed -i "/\[pike]/a\\$conf_controller_ip" /etc/ansible/hosts
        if [ "$conf_controller_role" == controller ]; then
            sed -i "/\[pike_controller]/a\\$conf_controller_ip" /etc/ansible/hosts
        fi
        if [ "$conf_controller_role" == compute ]; then
            sed -i "/\[pike_compute]/a\\$conf_controller_ip" /etc/ansible/hosts
        fi
    done
    mkdir /root/.ssh
    \cp $CONFIG_PATH/ssh/* /root/.ssh/
    chmod 700 /root/.ssh
    chmod 600 /root/.ssh/*
    chown -R root:root /root/.ssh
    echo "done"
}



### script start ###
case $1 in
--check)
    check_ansible
;;
--install)
    install_ansible
;;
*)
    usage
;;
esac
