#!/usr/bin/env bats

@test "Redis Instance Discovery without passwords" {
  result="$(../zabbix_agentd.d/zbx_redis_discovery.sh general | jq . > /dev/null 2>&1)"
  [ "$?" -eq 0 ]  
}

@test "Redis Instance Discovery with passwords" {
  result="$(../zabbix_agentd.d/zbx_redis_discovery.sh general "1234  " | jq . > /dev/null 2>&1)"
  [ "$?" -eq 0 ]
}

@test "Redis Instance Commands Stats without passwords" {
  result="$(../zabbix_agentd.d/zbx_redis_discovery.sh stats | jq . > /dev/null 2>&1)"
  [ "$?" -eq 0 ]
}

@test "Redis Instance Commands Stats with passwords" {
  result="$(../zabbix_agentd.d/zbx_redis_discovery.sh stats "1234  " | jq . > /dev/null 2>&1)"
  [ "$?" -eq 0 ]
}

@test "Redis Instance Replication without passwords" {
  result="$(../zabbix_agentd.d/zbx_redis_discovery.sh replication | jq . > /dev/null 2>&1)"
  [ "$?" -eq 0 ]
}

@test "Redis Instance Replications with passwords" {
  result="$(../zabbix_agentd.d/zbx_redis_discovery.sh replication "1234  " | jq . > /dev/null 2>&1)"
  [ "$?" -eq 0 ]
}
