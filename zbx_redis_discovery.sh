#!/bin/bash
IFS=$'\n'
PASSWORDS=( "$@" )
LIST=$(ps -eo uname,args | grep -v grep | grep redis-server | tr -s [:blank:] ":")
REDIS_CLI=$(whereis -b redis-cli | cut -d":" -f2 | tr -d [:space:])

echo -n '{"data":['

# PROBE DISCOVERED REDIS INSTACES #
discover_redis_instance() {
    HOST=$1
    PORT=$2
    PASSWORD=$3

    ALIVE=$($REDIS_CLI -h $HOST -p $PORT -a "$PASSWORD" ping)

    if [[ $ALIVE != "PONG" ]]; then
        return 0
    else
        INSTANCE=$($REDIS_CLI -h $HOST -p $PORT -a "$PASSWORD" info | grep config_file | rev | cut -d "/" -f1 | rev | tr -d [:space:] | tr -d ".conf" | tr [:lower:] [:upper:])
    fi

    echo $INSTANCE
}

# GENERATE ZABBIX DISCOVERY JSON REPONSE #
generate_discovery_json() {
    HOST=$1
    PORT=$2
    INSTANCE=$3

    echo -n '{'
    echo -n '"{#PORT}":"'$PORT'",'
    echo -n '"{#HOST}":"'$HOST'",'
    echo -n '"{#INSTANCE}":"'$INSTANCE'"'
    echo -n '},'
}

# GENERATE ALL REPORTS REQUIRED FOR REDIS MONITORING #
generate_redis_stats_report() {
    HOST=$1
    PORT=$2
    PASSWORD=$3

    REDIS_REPORT=$(stdbuf -oL $REDIS_CLI -h $HOST -p $PORT -a "$PASSWORD" info all | sed 's/\(cmdstat_.*:\)\(.*,\)\(.*,\)\(.*$\)/\1_\2\n\r\1_\3\n\r\1_\4/' | sed 's/\(db0.*:\)\(.*,\)\(.*,\)\(.*$\)/\1_\2\n\r\1_\3\n\r\1_\4/' | sed 's/\(slave.*:\)\(.*,\)\(.*,\)\(.*$\)/\1_ip=\2\n\r\1_port=\3\n\r\1_status=\4/' | sed 's/:_/_/g' | sed 's/,//g' | sed 's/=/:/g' &> /tmp/redis-$HOST-$PORT)
    REDIS_SLOWLOG_LEN=$(stdbuf -oL $REDIS_CLI -h $HOST -p $PORT -a "$PASSWORD" slowlog len | cut -d " " -f2 &> /tmp/redis-$HOST-$PORT-slowlog-len; $REDIS_CLI -h $HOST -p $PORT -a $PASSWORD slowlog reset > /dev/null  )
    REDIS_SLOWLOG_RAW=$(stdbuf -oL $REDIS_CLI -h $HOST -p $PORT -a "$PASSWORD" slowlog get &> /tmp/redis-$HOST-$PORT-slowlog-raw)
    REDIS_MAX_CLIENTS=$(stdbuf -oL $REDIS_CLI -h $HOST -p $PORT -a "$PASSWORD" config get *"maxclients"* | cut -d " " -f2 | sed -n 2p &> /tmp/redis-$HOST-$PORT-maxclients)
}

for s in $LIST; do
    HOST=$(echo $s | cut -d":" -f3)
    PORT=$(echo $s | cut -d":" -f4)

    # TRY PASSWORD PER EACH DISCOVERED INSTANCE
    if [[ ${#PASSWORDS[@]} -ne 0 ]]; then
        for (( i=0; i<${#PASSWORDS[@]}; i++ ));
        do
            PASSWORD=${PASSWORDS[$i]}
            INSTANCE=$(discover_redis_instance $HOST $PORT $PASSWORD)
            if [[ -n $INSTANCE ]]; then
                generate_redis_stats_report $HOST $PORT $PASSWORD
                generate_discovery_json $HOST $PORT $INSTANCE
                break
            fi
        done
    else
        INSTANCE=$(discover_redis_instance $HOST $PORT "")
        if [[ -n $INSTANCE ]]; then
            generate_redis_stats_report $HOST $PORT ""
            generate_discovery_json $HOST $PORT $INSTANCE
        fi
    fi
    unset
done | sed -e 's:\},$:\}:'
echo -n ']}'
echo ''
unset IFS
