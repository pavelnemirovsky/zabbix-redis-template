#!/bin/bash
IFS=$'\n'
PASSWORDS=( "$@" )
LIST=$(ps -eo uname,args | grep -v grep | grep redis | tr -s [:blank:] ":")

echo -n '{"data":['

for s in $LIST; do
    IP=$(echo $s | cut -d":" -f3)
    PORT=$(echo $s | cut -d":" -f4)

    # TRY PASSWORD PER EACH DISCOVERED INSTANCE
    if [[ ${#PASSWORDS[@]} -ne 0 ]]; then
        for (( i=0; i<${#PASSWORDS[@]}; i++ ));
        do
            INSTANCE=$(redis-cli -h $IP -p $PORT -a ${PASSWORDS[$i]} info | grep config_file | rev | cut -d "/" -f1 | rev | tr -d [:space:] | tr -d ".conf" | tr [:lower:] [:upper:])
            if [ $? -eq 0 ]; then
                stdbuf -oL redis-cli -h $IP -p $PORT -a ${PASSWORDS[$i]} info all &> /tmp/redis-$INSTANCE-$PORT
                break
            fi
        done
    else
        echo "here"
        INSTANCE=$(redis-cli -h $IP -p $PORT  info | grep config_file | rev | cut -d "/" -f1 | rev | tr -d [:space:] | tr -d ".conf" | tr [:lower:] [:upper:])
        stdbuf -oL redis-cli -h $IP -p $PORT  info all &> /tmp/redis-$INSTANCE-$PORT
    fi

    echo -n '{"{#INSTANCE}":"'$INSTANCE'"},'
    echo -n '{"{#HOST}":"'$IP'"},'
    echo -n '{"{#PORT}":"'$PORT'"},'

done | sed -e 's:\},$:\}:'
echo -n ']}'
echo ''
unset IFS
