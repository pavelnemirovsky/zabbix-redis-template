#!/bin/bash
IFS=$'\n'
PASSWORDS=( "$@" )
LIST=$(ps -eo uname,args | grep -v grep | grep redis-server | tr -s [:blank:] ":")

echo -n '{"data":['

discover_redis_instance() {
    HOST=$1
    PORT=$2
    PASSWORD=$3

    if [[ $PASSWORD != "" ]]; then
        ALIVE=$(redis-cli -h $HOST -p $PORT -a $PASSWORD ping)
    else
        ALIVE=$(redis-cli -h $HOST -p $PORT ping)
    fi

    if [[ $ALIVE != "PONG" ]]; then
        return 0
    elif [[ $PASSWORD != "" ]]; then
        INSTANCE=$(redis-cli -h $HOST -p $PORT -a $PASSWORD info | grep config_file | rev | cut -d "/" -f1 | rev | tr -d [:space:] | tr -d ".conf" | tr [:lower:] [:upper:])
    else
        INSTANCE=$(redis-cli -h $HOST -p $PORT info | grep config_file | rev | cut -d "/" -f1 | rev | tr -d [:space:] | tr -d ".conf" | tr [:lower:] [:upper:])
    fi

    echo $INSTANCE
}

generate_json() {
    HOST=$1
    PORT=$2
    INSTANCE=$3

    echo -n '{'
    echo -n '"#PORT":"'$PORT'",'
    echo -n '"#HOST":"'$HOST'",'
    echo -n '"#INSTANCE":"'$INSTANCE'"'
    echo -n '},'
}

for s in $LIST; do
    HOST=$(echo $s | cut -d":" -f3)
    PORT=$(echo $s | cut -d":" -f4)

    # TRY PASSWORD PER EACH DISCOVERED INSTANCE
    if [[ ${#PASSWORDS[@]} -ne 0 ]]; then
        for (( i=0; i<${#PASSWORDS[@]}; i++ ));
        do
            INSTANCE=$(discover_redis_instance $HOST $PORT ${PASSWORDS[$i]})
            if [[ -n $INSTANCE ]]; then
                stdbuf -oL redis-cli -h $HOST -p $PORT -a ${PASSWORDS[$i]} info all &> /tmp/redis-$HOST-$PORT
                generate_json $HOST $PORT $INSTANCE
                break
            fi
        done
    else
        INSTANCE=$(discover_redis_instance $HOST $PORT)
        if [[ -n $INSTANCE ]]; then
            stdbuf -oL redis-cli -h $HOST -p $PORT  info all &> /tmp/redis-$HOST-$PORT
            generate_json $HOST $PORT $INSTANCE
        fi
    fi

done | sed -e 's:\},$:\}:'
echo -n ']}'
echo ''
unset IFS
