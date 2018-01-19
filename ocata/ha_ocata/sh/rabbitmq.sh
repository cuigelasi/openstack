#!/bin/bash
rabbitmqctl set_policy ha-all '^(?!amq\.).*' '{"ha-mode": "all", "ha-sync-mode":"automatic"}'
rabbitmqctl add_user openstack RABBIT_PASS
rabbitmqctl set_permissions openstack ".*" ".*" ".*"
