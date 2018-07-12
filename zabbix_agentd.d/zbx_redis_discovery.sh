#!/bin/bash
ARGS=("$@")
DISCOVERY_TYPE=$1
REDIS_CLI_DEFAULT_PATH="/usr/bin/redis-cli"
STBDBUF_DEFAULT_PATH="/usr/bin/stdbuf"
# USE FIRST ARGUMENT TO UNDERSTAND WHICH DISCOVERY TO PERFORM
shift
IFS=$'\n'
PASSWORDS=( "$@" )
LIST=$(ps -eo user,args | grep -v grep | grep redis-server | tr -s [:blank:] ":")

if [[ " ${ARGS[@]} " =~ " debug " ]]; then
    set -x
else
    set -e  # RUDIMENTARY ERROR MECHANISM
fi

# REQUIRED UTILS TO BE ABLE TO RUN
if [ -e /tmp/redis-cli ]; then
    REDIS_CLI=$(cat /tmp/redis-cli)
else
    REDIS_CLI=$(locate redis-cli | head -n 1)
    if [ "$REDIS_CLI" = "" ]; then
        if [ -e $REDIS_CLI_DEFAULT_PATH ]; then
            REDIS_CLI_FILE=$(echo $REDIS_CLI_DEFAULT_PATH > /tmp/redis-cli)
        else
            echo "REDIS-CLI not found ...."
            exit 1
        fi
    else
        REDIS_CLI_FILE=$(echo $REDIS_CLI > /tmp/redis-cli)
    fi
fi

if [ "$DISCOVERY_TYPE" != "general" ] && [ "$DISCOVERY_TYPE" != "stats" ] && [ "$DISCOVERY_TYPE" != "replication" ]; then
    echo "USAGE: ./zbx_redis_discovery.sh where"
    echo "general - argument generate report with discovered instances"
    echo "stats - generates report for avalable commands"
    echo "replication - generates report for avalable slaves"
    exit 1
fi

# PROBE DISCOVERED REDIS INSTACES - TO GET INSTANCE NAME#
discover_redis_instance() {
    HOST=$1
    PORT=$2
    PASSWORD=$3

    ALIVE=$($REDIS_CLI -h $HOST -p $PORT -a "$PASSWORD" ping)

    if [[ $ALIVE != "PONG" ]]; then
        return 1
    else
        INSTANCE=$($REDIS_CLI -h $HOST -p $PORT -a "$PASSWORD" info | grep config_file | cut -d ":" -f2 | sed 's/.conf//g' | rev | cut -d "/" -f1 | rev | tr -d [:space:] | tr '[:lower:]' '[:upper:]')
        # WHEN UNABLE TO IDENTIFY INSTANCE NAME BASED ON CONFIG
        if [ "$INSTANCE" = "" ]; then
            INSTANCE=$(echo "$HOST:$PORT")
        fi
        INSTANCE_RDB_PATH=$($REDIS_CLI -h $HOST -p $PORT -a "$PASSWORD" config get "dir" | cut -d " " -f2 | sed -n 2p)
        INSTANCE_RDB_FILE=$($REDIS_CLI -h $HOST -p $PORT -a "$PASSWORD" config get "dbfilename" | cut -d " " -f2 | sed -n 2p)
    fi

    echo $INSTANCE
}

# PROBE DISCOVERED REDIS INSTACES - TO GET RDB DATABASE#
discover_redis_rdb_database() {
    HOST=$1
    PORT=$2
    PASSWORD=$3

    ALIVE=$($REDIS_CLI -h $HOST -p $PORT -a "$PASSWORD" ping)

    if [[ $ALIVE != "PONG" ]]; then
        return 1
    else
        INSTANCE_RDB_PATH=$($REDIS_CLI -h $HOST -p $PORT -a "$PASSWORD" config get "dir" | cut -d " " -f2 | sed -n 2p)
        INSTANCE_RDB_FILE=$($REDIS_CLI -h $HOST -p $PORT -a "$PASSWORD" config get "dbfilename" | cut -d " " -f2 | sed -n 2p)
    fi

    echo $INSTANCE_RDB_PATH/$INSTANCE_RDB_FILE
}

discover_redis_available_commands() {
    HOST=$1
    PORT=$2
    PASSWORD=$3

    ALIVE=$($REDIS_CLI -h $HOST -p $PORT -a "$PASSWORD" ping)

    if [[ $ALIVE != "PONG" ]]; then
        return 1
    else
        REDIS_COMMANDS=$($REDIS_CLI -h $HOST -p $PORT -a "$PASSWORD" info all | grep cmdstat | cut -d":" -f1)
    fi

    ( IFS=$'\n'; echo "${REDIS_COMMANDS[*]}" )
}

discover_redis_available_slaves() {
    HOST=$1
    PORT=$2
    PASSWORD=$3

    ALIVE=$($REDIS_CLI -h $HOST -p $PORT -a "$PASSWORD" ping)

    if [[ $ALIVE != "PONG" ]]; then
        return 1
    else
        REDIS_SLAVES=$($REDIS_CLI -h $HOST -p $PORT -a "$PASSWORD" info all | grep ^slave | cut -d ":" -f1 | grep [0-1024])
    fi

    ( IFS=$'\n'; echo "${REDIS_SLAVES[*]}" )
}

# GENERATE ZABBIX DISCOVERY JSON REPONSE #
generate_general_discovery_json() {
    HOST=$1
    PORT=$2
    INSTANCE=$3
    RDB_PATH=$4

    echo -n '{'
    echo -n '"{#HOST}":"'$HOST'",'
    echo -n '"{#PORT}":"'$PORT'",'
    echo -n '"{#INSTANCE}":"'$INSTANCE'",'
    echo -n '"{#RDB_PATH}":"'$RDB_PATH'"'
    echo -n '},'
}

# GENERATE ZABBIX DISCOVERY JSON REPONSE #
generate_commands_discovery_json() {
    HOST=$1
    PORT=$2
    COMMAND=$3
    INSTANCE=$4

    echo -n '{'
    echo -n '"{#HOST}":"'$HOST'",'
    echo -n '"{#PORT}":"'$PORT'",'
    echo -n '"{#COMMAND}":"'$COMMAND'",'
    echo -n '"{#INSTANCE}":"'$INSTANCE'"'
    echo -n '},'
}

# GENERATE ZABBIX DISCOVERY JSON REPONSE #
generate_replication_discovery_json() {
    HOST=$1
    PORT=$2
    SLAVE=$3
    INSTANCE=$4

    echo -n '{'
    echo -n '"{#HOST}":"'$HOST'",'
    echo -n '"{#PORT}":"'$PORT'",'
    echo -n '"{#SLAVE}":"'$SLAVE'",'
    echo -n '"{#INSTANCE}":"'$INSTANCE'"'
    echo -n '},'
}


# GENERATE ALL REPORTS REQUIRED FOR REDIS MONITORING #
generate_redis_stats_report() {
    HOST=$1
    PORT=$2
    PASSWORD=$3

    # REDIS MAIN REPORT - INFO ALL
    local REDIS_REPORT_RESULT="/tmp/redis-$HOST-$PORT"
    local REDIS_REPORT_RESULT_TMP="/tmp/redis-$HOST-$PORT.tmp"
    REDIS_REPORT=$($REDIS_CLI -h $HOST -p $PORT -a "$PASSWORD" info all > $REDIS_REPORT_RESULT_TMP)
    REDIS_REPORT_RC=$?

    # REDIS SLOW LOG
    local REDIS_SLOWLOG_LEN_RESULT="/tmp/redis-$HOST-$PORT-slowlog-len"
    local REDIS_SLOWLOG_LEN_RESULT_TMP="/tmp/redis-$HOST-$PORT-slowlog-len.tmp"
    REDIS_SLOWLOG_LEN=$($REDIS_CLI -h $HOST -p $PORT -a "$PASSWORD" slowlog len | cut -d " " -f2 > $REDIS_SLOWLOG_LEN_RESULT_TMP; $REDIS_CLI -h $HOST -p $PORT -a $PASSWORD slowlog reset > /dev/null )
    REDIS_SLOWLOG_LEN_RC=$?

    # REDIS SLOW LOG REPORT
    local REDIS_SLOWLOG_RAW_RESULT="/tmp/redis-$HOST-$PORT-slowlog-raw"
    local REDIS_SLOWLOG_RAW_RESULT_TMP="/tmp/redis-$HOST-$PORT-slowlog-raw.tmp"
    REDIS_SLOWLOG_RAW=$($REDIS_CLI -h $HOST -p $PORT -a "$PASSWORD" slowlog get > $REDIS_SLOWLOG_RAW_RESULT_TMP)
    REDIS_SLOWLOG_RAW_RC=$?

    # REDIS MAX CLIENT REPORT
    local REDIS_MAX_CLIENTS_RESULT="/tmp/redis-$HOST-$PORT-maxclients"
    local REDIS_MAX_CLIENTS_RESULT_TMP="/tmp/redis-$HOST-$PORT-maxclients.tmp"
    REDIS_MAX_CLIENTS=$($REDIS_CLI -h $HOST -p $PORT -a "$PASSWORD" config get *"maxclients"* | cut -d " " -f2 | sed -n 2p > $REDIS_MAX_CLIENTS_RESULT_TMP)
    REDIS_MAX_CLIENTS_RC=$?

    if [[ -e $REDIS_REPORT_RESULT_TMP ]] && [[ $REDIS_REPORT_RC -eq 0 ]];then
        REDIS_REPORT_DUMP=$(mv $REDIS_REPORT_RESULT_TMP $REDIS_REPORT_RESULT)
        if [[ $? -ne 0 ]]; then
            return 1
        fi
    fi

    if [[ -e $REDIS_SLOWLOG_LEN_RESULT_TMP ]] && [[ $REDIS_SLOWLOG_LEN -eq 0 ]];then
        REDIS_REPORT_DUMP=$(mv $REDIS_SLOWLOG_LEN_RESULT_TMP $REDIS_SLOWLOG_LEN_RESULT)
        if [[ $? -ne 0 ]]; then
            return 2
        fi
    fi

    if [[ -e $REDIS_MAX_CLIENTS_RESULT_TMP ]] && [[ $REDIS_SLOWLOG_RAW_RC -eq 0 ]];then
        REDIS_REPORT_DUMP=$(mv $REDIS_SLOWLOG_RAW_RESULT_TMP $REDIS_SLOWLOG_RAW_RESULT)
        if [[ $? -ne 0 ]]; then
            return 2
        fi
    fi

    if [[ -e $REDIS_MAX_CLIENTS_RESULT_TMP ]] && [[ $REDIS_MAX_CLIENTS_RC -eq 0 ]];then
        REDIS_REPORT_DUMP=$(mv $REDIS_MAX_CLIENTS_RESULT_TMP $REDIS_MAX_CLIENTS_RESULT)
        if [[ $? -ne 0 ]]; then
            return 2
        fi
    fi

}

# MAIN LOOP #

echo -n '{"data":['
for s in $LIST; do
    HOST=$(echo $s | sed 's/*/127.0.0.1/g' | cut -d":" -f3)
    PORT=$(echo $s | sed 's/*/127.0.0.1/g' | cut -d":" -f4)

    # TRY PASSWORD PER EACH DISCOVERED INSTANCE
    if [[ ${#PASSWORDS[@]} -ne 0 ]]; then
        for (( i=0; i<${#PASSWORDS[@]}; i++ ));
        do
            PASSWORD=${PASSWORDS[$i]}
            INSTANCE=$(discover_redis_instance $HOST $PORT $PASSWORD)
            RDB_PATH=$(discover_redis_rdb_database $HOST $PORT $PASSWORD)
            COMMANDS=$(discover_redis_available_commands $HOST $PORT $PASSWORD)
            SLAVES=$(discover_redis_available_slaves $HOST $PORT $PASSWORD)

            if [[ -n $INSTANCE ]]; then

                # DECIDE WHICH REPORT TO GENERATE FOR DISCOVERY
                if [[ $DISCOVERY_TYPE == "general" ]]; then
                    generate_redis_stats_report $HOST $PORT $PASSWORD
                    generate_general_discovery_json $HOST $PORT $INSTANCE $RDB_PATH
                elif [[ $DISCOVERY_TYPE == "stats" ]]; then
                    for COMMAND in ${COMMANDS}; do
                        generate_commands_discovery_json $HOST $PORT $COMMAND $INSTANCE
                    done
                elif [[ $DISCOVERY_TYPE == "replication" ]]; then
                    for SLAVE in ${SLAVES}; do
                        generate_replication_discovery_json $HOST $PORT $SLAVE $INSTANCE
                    done
                fi
            fi
        done
    else
        INSTANCE=$(discover_redis_instance $HOST $PORT "")
        RDB_PATH=$(discover_redis_rdb_database $HOST $PORT "")
        COMMANDS=$(discover_redis_available_commands $HOST $PORT "")
        SLAVES=$(discover_redis_available_slaves $HOST $PORT "")

        if [[ -n $INSTANCE ]]; then

            # DECIDE WHICH REPORT TO GENERATE FOR DISCOVERY
            if [[ $DISCOVERY_TYPE == "general" ]]; then
                generate_redis_stats_report $HOST $PORT ""
                generate_general_discovery_json $HOST $PORT $INSTANCE $RDB_PATH
            elif [[ $DISCOVERY_TYPE == "stats" ]]; then
                for COMMAND in ${COMMANDS}; do
                    generate_commands_discovery_json $HOST $PORT $COMMAND $INSTANCE
                done
            elif [[ $DISCOVERY_TYPE == "replication" ]]; then
                for SLAVE in ${SLAVES}; do
                    generate_replication_discovery_json $HOST $PORT $SLAVE $INSTANCE
                done
            fi
        fi
    fi
    unset
done | sed -e 's:\},$:\}:'
echo -n ']}'
echo ''
unset IFS
