#/bin/bash
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

INSTALL_PACKAGE_PATH=`getPath`
NOVA_PATH="$INSTALL_PACKAGE_PATH/confs/nova"

source /home/admin-openrc.sh
local_id=`neutron net-list | grep local_net1 | awk '{print $2}'`

VM(){
    check=`nova list | grep bachang | awk '{print $4}'`
    if [ "$check" != "bachang" ]; then
        echo "准备创建bachang云主机"
        nova boot --flavor 2 --image $image_id --nic net-id="$local_id" --security_group default bachang      
        while true
        do
            state=`nova list | grep bachang | awk '{print $6}'`
            if [ "$state" = "ACTIVE" ]; then
                echo "$image_name已完成"
                sleep 3
                nova delete bachang
                sleep 3
                break
            fi
        done
    fi
}

While_read_LINE(){
file="$NOVA_PATH/create_vm.txt"
while read line
do
   image_id=`echo $line | awk '{print $1}'`
   image_name=`echo $line | awk '{print $2}'`
   VM $image_id $image_name
done < $file
}

While_read_LINE

