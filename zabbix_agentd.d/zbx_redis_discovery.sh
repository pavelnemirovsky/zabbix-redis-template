#!/usr/bin/env bash
# Zabbix LLD helper for Redis / KeyDB: discovers instances from ps(1), probes with redis-cli,
# and optionally validates OS process + server-reported executable to reduce false positives.

set -o pipefail 2>/dev/null || true
set -o noglob 2>/dev/null || true
setopt noglob &>/dev/null || true

# Locale: set once and export so every child (ps, grep, redis-cli, awk, sed) inherits it.
# Avoids repeated locale initialization and UTF-8 collation cost; keeps tool output stable for parsing.
export LC_ALL=C
export LANGUAGE=C

REDIS_CLI_DEFAULT_PATH="/usr/bin/redis-cli"

usage() {
    cat <<'EOF'
Usage: zbx_redis_discovery.sh <general|stats|replication> [password ...] [debug]

  general       Low-level discovery: emit {#HOST},{#PORT},{#INSTANCE},{#RDB_PATH},
                {#PROCESS_NAME},{#PROCESS_PATH}. Writes metric cache under /tmp/redis-*.

  stats         Discover per-command cmdstat keys ({#COMMAND}) for the template.

  replication   Discover replication slave keys ({#SLAVE}) from INFO.

  password      Optional. One or more passwords; each candidate instance is probed
                with each password until PONG (same order as given).

  debug         Optional. Enables bash trace (set -x).

Environment / paths:
  LC_ALL=C and LANGUAGE=C are exported at startup (single parse; inherited by subprocesses)
  for predictable output and lower overhead than user locales.
  redis-cli is read from /tmp/redis-cli (first line) if present; otherwise locate(1),
  then command -v redis-cli, then REDIS_CLI_DEFAULT_PATH.

Discovery guards (reduce false positives under load):
  - If ps(1) reports a numeric PID, kill -0 on that PID must succeed (process still alive).
  - On Linux, if /proc/PID/exe is readable, that is accepted as proof of the server binary.
  - Otherwise the INFO executable path must refer to an existing regular file on this host.

Exit codes:
  0  Success (JSON printed; may be {"data":[]}).
  1  Missing/invalid arguments, or redis-cli not found.
EOF
}

ARGS=("$@")
DISCOVERY_TYPE=""
PASSWORDS=()
DEBUG=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help|help)
            usage
            exit 0
            ;;
        debug)
            DEBUG=1
            shift
            ;;
        general|stats|replication)
            DISCOVERY_TYPE="$1"
            shift
            PASSWORDS=("$@")
            break
            ;;
        *)
            if [[ -z "$DISCOVERY_TYPE" ]]; then
                DISCOVERY_TYPE="$1"
                shift
                PASSWORDS=("$@")
                break
            fi
            PASSWORDS+=("$1")
            shift
            ;;
    esac
done

if [[ "$DEBUG" -eq 1 ]] || [[ " ${ARGS[*]} " == *" debug "* ]]; then
    set -x
fi

if [[ -z "$DISCOVERY_TYPE" ]] || [[ "$DISCOVERY_TYPE" != "general" && "$DISCOVERY_TYPE" != "stats" && "$DISCOVERY_TYPE" != "replication" ]]; then
    usage >&2
    exit 1
fi

# Remove debug from passwords if passed as only extra token
declare -a PASS_CLEAN=()
for p in "${PASSWORDS[@]}"; do
    [[ "$p" == "debug" ]] && continue
    PASS_CLEAN+=("$p")
done
PASSWORDS=("${PASS_CLEAN[@]}")

IFS=$'\n'
LIST=$(
    ps -eo pid,user,args 2>/dev/null | grep -v grep | grep -E -i -w 'keydb-server|redis-server' | tr -s '[:blank:]' ':'
)

# REQUIRED UTILS TO BE ABLE TO RUN
if [[ -e /tmp/redis-cli ]]; then
    REDIS_CLI=$(head -n 1 /tmp/redis-cli)
else
    REDIS_CLI=""
    if command -v locate &>/dev/null; then
        REDIS_CLI=$(locate redis-cli 2>/dev/null | grep -E '(^|/)redis-cli$' | head -n 1)
    fi
    if [[ -z "$REDIS_CLI" ]] && command -v redis-cli &>/dev/null; then
        REDIS_CLI=$(command -v redis-cli)
    fi
    if [[ -z "$REDIS_CLI" ]]; then
        if [[ -e "$REDIS_CLI_DEFAULT_PATH" ]]; then
            REDIS_CLI="$REDIS_CLI_DEFAULT_PATH"
        else
            echo '{"data":[]}'
            exit 1
        fi
    fi
    echo "$REDIS_CLI" >/tmp/redis-cli
fi

if [[ ! -f "$REDIS_CLI" ]] && [[ ! -x "$REDIS_CLI" ]]; then
    echo '{"data":[]}'
    exit 1
fi

# --- Parse ps line: first field may be PID; host/port fields shift by +1 when PID present ---
extract_pid_host_port() {
    local s="$1"
    local coloned first pid="" host port
    coloned=$(echo "$s" | sed 's/\*/127.0.0.1/g' | tr -s '[:blank:]' ':')
    first=$(echo "$coloned" | cut -d: -f1)
    if [[ "$first" =~ ^[0-9]+$ ]]; then
        pid="$first"
        host=$(echo "$coloned" | cut -d: -f4)
        port=$(echo "$coloned" | cut -d: -f5)
    else
        host=$(echo "$coloned" | cut -d: -f3)
        port=$(echo "$coloned" | cut -d: -f4)
    fi
    printf '%s\t%s\t%s\n' "$pid" "$host" "$port"
}

# Verify OS process is alive; on Linux prefer /proc/PID/exe; otherwise require INFO path on disk.
verify_process_and_binary() {
    local pid="$1"
    local info_executable="$2"

    if [[ -n "$pid" ]] && [[ "$pid" =~ ^[0-9]+$ ]]; then
        if ! kill -0 "$pid" 2>/dev/null; then
            return 1
        fi
    fi

    if [[ -n "$pid" ]] && [[ "$pid" =~ ^[0-9]+$ ]] && { [[ -r "/proc/$pid/exe" ]] || [[ -L "/proc/$pid/exe" ]]; }; then
        return 0
    fi

    if [[ -n "$info_executable" ]] && [[ -f "$info_executable" ]]; then
        return 0
    fi

    return 1
}

# PROBE DISCOVERED REDIS INSTANCES - TO GET INSTANCE_META NAME#
discover_redis_instance() {
    local HOST="$1"
    local PORT="$2"
    local PASSWORD="$3"

    local ALIVE INSTANCE INSTANCE_PROCESS_NAME INSTANCE_PROCESS_PATH FULL_PROCESS

    ALIVE=$($REDIS_CLI -h "$HOST" -p "$PORT" ${PASSWORD:+-a "$PASSWORD"} ping 2>/dev/null)

    if [[ "$ALIVE" != "PONG" ]]; then
        return 1
    fi

    INSTANCE=$($REDIS_CLI -h "$HOST" -p "$PORT" ${PASSWORD:+-a "$PASSWORD"} info 2>/dev/null | grep '^config_file:' | cut -d: -f2- | sed 's/\r$//' | sed 's/.conf$//' | rev | cut -d/ -f1 | rev | tr -d '[:space:]' | tr '[:lower:]' '[:upper:]')
    if [[ -z "$INSTANCE" ]]; then
        INSTANCE="${HOST}:${PORT}"
    fi

    FULL_PROCESS=$($REDIS_CLI -h "$HOST" -p "$PORT" ${PASSWORD:+-a "$PASSWORD"} info 2>/dev/null | grep '^executable:' | cut -d: -f2- | sed 's/\r$//' | tr -d '[:space:]')

    INSTANCE_PROCESS_NAME="unknown"
    INSTANCE_PROCESS_PATH="unknown"
    if [[ -n "$FULL_PROCESS" ]]; then
        INSTANCE_PROCESS_NAME=$(basename "$FULL_PROCESS")
        INSTANCE_PROCESS_PATH=$(dirname "$FULL_PROCESS")
    fi

    echo "$INSTANCE;$INSTANCE_PROCESS_NAME;$INSTANCE_PROCESS_PATH;$FULL_PROCESS"
}

# PROBE DISCOVERED REDIS INSTANCES - TO GET RDB DATABASE#
discover_redis_rdb_database() {
    local HOST="$1"
    local PORT="$2"
    local PASSWORD="$3"
    local ALIVE INSTANCE_RDB_PATH INSTANCE_RDB_FILE

    ALIVE=$($REDIS_CLI -h "$HOST" -p "$PORT" ${PASSWORD:+-a "$PASSWORD"} ping 2>/dev/null)

    if [[ "$ALIVE" != "PONG" ]]; then
        return 1
    fi

    INSTANCE_RDB_PATH=$($REDIS_CLI -h "$HOST" -p "$PORT" ${PASSWORD:+-a "$PASSWORD"} config get "dir" 2>/dev/null | awk 'NR==2{print $2}')
    INSTANCE_RDB_FILE=$($REDIS_CLI -h "$HOST" -p "$PORT" ${PASSWORD:+-a "$PASSWORD"} config get "dbfilename" 2>/dev/null | awk 'NR==2{print $2}')

    echo "${INSTANCE_RDB_PATH}/${INSTANCE_RDB_FILE}"
}

discover_redis_available_commands() {
    local HOST="$1"
    local PORT="$2"
    local PASSWORD="$3"
    local ALIVE REDIS_COMMANDS

    ALIVE=$($REDIS_CLI -h "$HOST" -p "$PORT" ${PASSWORD:+-a "$PASSWORD"} ping 2>/dev/null)

    if [[ "$ALIVE" != "PONG" ]]; then
        return 1
    fi

    REDIS_COMMANDS=$($REDIS_CLI -h "$HOST" -p "$PORT" ${PASSWORD:+-a "$PASSWORD"} info all 2>/dev/null | grep cmdstat | cut -d: -f1)

    (IFS=$'\n'; echo "${REDIS_COMMANDS[*]}")
}

discover_redis_available_slaves() {
    local HOST="$1"
    local PORT="$2"
    local PASSWORD="$3"
    local ALIVE REDIS_SLAVES

    ALIVE=$($REDIS_CLI -h "$HOST" -p "$PORT" ${PASSWORD:+-a "$PASSWORD"} ping 2>/dev/null)

    if [[ "$ALIVE" != "PONG" ]]; then
        return 1
    fi

    REDIS_SLAVES=$($REDIS_CLI -h "$HOST" -p "$PORT" ${PASSWORD:+-a "$PASSWORD"} info replication 2>/dev/null | grep -E '^slave[0-9]+:' | cut -d: -f1)

    (IFS=$'\n'; echo "${REDIS_SLAVES[*]}")
}

# GENERATE ZABBIX DISCOVERY JSON RESPONSE #
generate_general_discovery_json() {
    local HOST="$1"
    local PORT="$2"
    local INSTANCE="$3"
    local RDB_PATH="$4"
    local PROCESS_NAME="$5"
    local PROCESS_PATH="$6"

    echo -n '{'
    echo -n '"{#HOST}":"'"$HOST"'",'
    echo -n '"{#PORT}":"'"$PORT"'",'
    echo -n '"{#INSTANCE}":"'"$INSTANCE"'",'
    echo -n '"{#RDB_PATH}":"'"$RDB_PATH"'",'
    echo -n '"{#PROCESS_NAME}":"'"$PROCESS_NAME"'",'
    echo -n '"{#PROCESS_PATH}":"'"$PROCESS_PATH"'"'
    echo -n '},'
}

# GENERATE ZABBIX DISCOVERY JSON RESPONSE #
generate_commands_discovery_json() {
    local HOST="$1"
    local PORT="$2"
    local COMMAND="$3"
    local INSTANCE="$4"

    echo -n '{'
    echo -n '"{#HOST}":"'"$HOST"'",'
    echo -n '"{#PORT}":"'"$PORT"'",'
    echo -n '"{#COMMAND}":"'"$COMMAND"'",'
    echo -n '"{#INSTANCE}":"'"$INSTANCE"'"'
    echo -n '},'
}

# GENERATE ZABBIX DISCOVERY JSON RESPONSE #
generate_replication_discovery_json() {
    local HOST="$1"
    local PORT="$2"
    local SLAVE="$3"
    local INSTANCE="$4"

    echo -n '{'
    echo -n '"{#HOST}":"'"$HOST"'",'
    echo -n '"{#PORT}":"'"$PORT"'",'
    echo -n '"{#SLAVE}":"'"$SLAVE"'",'
    echo -n '"{#INSTANCE}":"'"$INSTANCE"'"'
    echo -n '},'
}

# GENERATE ALL REPORTS REQUIRED FOR REDIS MONITORING #
generate_redis_stats_report() {
    local HOST="$1"
    local PORT="$2"
    local PASSWORD="$3"

    local REDIS_REPORT_RESULT="/tmp/redis-$HOST-$PORT"
    local REDIS_REPORT_RESULT_TMP="/tmp/redis-$HOST-$PORT.tmp"
    local REDIS_SLOWLOG_LEN_RESULT="/tmp/redis-$HOST-$PORT-slowlog-len"
    local REDIS_SLOWLOG_LEN_RESULT_TMP="/tmp/redis-$HOST-$PORT-slowlog-len.tmp"
    local REDIS_SLOWLOG_RAW_RESULT="/tmp/redis-$HOST-$PORT-slowlog-raw"
    local REDIS_SLOWLOG_RAW_RESULT_TMP="/tmp/redis-$HOST-$PORT-slowlog-raw.tmp"
    local REDIS_MAX_CLIENTS_RESULT="/tmp/redis-$HOST-$PORT-maxclients"
    local REDIS_MAX_CLIENTS_RESULT_TMP="/tmp/redis-$HOST-$PORT-maxclients.tmp"

    $REDIS_CLI -h "$HOST" -p "$PORT" ${PASSWORD:+-a "$PASSWORD"} info all 2>/dev/null >"$REDIS_REPORT_RESULT_TMP"
    local REDIS_REPORT_RC=$?

    $REDIS_CLI -h "$HOST" -p "$PORT" ${PASSWORD:+-a "$PASSWORD"} slowlog len 2>/dev/null | awk '{print $2}' >"$REDIS_SLOWLOG_LEN_RESULT_TMP"
    local REDIS_SLOWLOG_LEN_RC=$?
    $REDIS_CLI -h "$HOST" -p "$PORT" ${PASSWORD:+-a "$PASSWORD"} slowlog reset 2>/dev/null >/dev/null || true

    $REDIS_CLI -h "$HOST" -p "$PORT" ${PASSWORD:+-a "$PASSWORD"} slowlog get 2>/dev/null >"$REDIS_SLOWLOG_RAW_RESULT_TMP"
    local REDIS_SLOWLOG_RAW_RC=$?

    $REDIS_CLI -h "$HOST" -p "$PORT" ${PASSWORD:+-a "$PASSWORD"} config get maxclients 2>/dev/null | awk 'NR==2{print $2}' >"$REDIS_MAX_CLIENTS_RESULT_TMP"
    local REDIS_MAX_CLIENTS_RC=$?

    if [[ -e "$REDIS_REPORT_RESULT_TMP" ]] && [[ "$REDIS_REPORT_RC" -eq 0 ]]; then
        mv "$REDIS_REPORT_RESULT_TMP" "$REDIS_REPORT_RESULT" || return 1
    fi

    if [[ -e "$REDIS_SLOWLOG_LEN_RESULT_TMP" ]] && [[ "$REDIS_SLOWLOG_LEN_RC" -eq 0 ]]; then
        mv "$REDIS_SLOWLOG_LEN_RESULT_TMP" "$REDIS_SLOWLOG_LEN_RESULT" || return 2
    fi

    if [[ -e "$REDIS_SLOWLOG_RAW_RESULT_TMP" ]] && [[ "$REDIS_SLOWLOG_RAW_RC" -eq 0 ]]; then
        mv "$REDIS_SLOWLOG_RAW_RESULT_TMP" "$REDIS_SLOWLOG_RAW_RESULT" || return 2
    fi

    if [[ -e "$REDIS_MAX_CLIENTS_RESULT_TMP" ]] && [[ "$REDIS_MAX_CLIENTS_RC" -eq 0 ]]; then
        mv "$REDIS_MAX_CLIENTS_RESULT_TMP" "$REDIS_MAX_CLIENTS_RESULT" || return 2
    fi
}

# MAIN LOOP #

echo -n '{"data":['
for s in $LIST; do
    IFS=$'\t' read -r PID HOST PORT <<<"$(extract_pid_host_port "$s")"

    [[ -z "$HOST" || -z "$PORT" ]] && continue

    # TRY PASSWORD PER EACH DISCOVERED INSTANCE
    if [[ ${#PASSWORDS[@]} -ne 0 ]]; then
        for ((i = 0; i < ${#PASSWORDS[@]}; i++)); do
            PASSWORD="${PASSWORDS[$i]}"
            _inst_line=$(discover_redis_instance "$HOST" "$PORT" "$PASSWORD") || continue
            IFS=';' read -r INSTANCE INSTANCE_PROCESS_NAME INSTANCE_PROCESS_PATH FULL_EX <<<"$_inst_line"

            if ! verify_process_and_binary "$PID" "$FULL_EX"; then
                break
            fi

            RDB_PATH=$(discover_redis_rdb_database "$HOST" "$PORT" "$PASSWORD")
            COMMANDS=$(discover_redis_available_commands "$HOST" "$PORT" "$PASSWORD")
            SLAVES=$(discover_redis_available_slaves "$HOST" "$PORT" "$PASSWORD")

            if [[ -n "$INSTANCE" ]]; then
                if [[ "$DISCOVERY_TYPE" == "general" ]]; then
                    generate_redis_stats_report "$HOST" "$PORT" "$PASSWORD"
                    generate_general_discovery_json "$HOST" "$PORT" "$INSTANCE" "$RDB_PATH" "$INSTANCE_PROCESS_NAME" "$INSTANCE_PROCESS_PATH"
                elif [[ "$DISCOVERY_TYPE" == "stats" ]]; then
                    for COMMAND in ${COMMANDS}; do
                        generate_commands_discovery_json "$HOST" "$PORT" "$COMMAND" "$INSTANCE"
                    done
                elif [[ "$DISCOVERY_TYPE" == "replication" ]]; then
                    for SLAVE in ${SLAVES}; do
                        generate_replication_discovery_json "$HOST" "$PORT" "$SLAVE" "$INSTANCE"
                    done
                fi
                break
            fi
        done
    else
        _inst_line=$(discover_redis_instance "$HOST" "$PORT" "") || continue
        IFS=';' read -r INSTANCE INSTANCE_PROCESS_NAME INSTANCE_PROCESS_PATH FULL_EX <<<"$_inst_line"

        if ! verify_process_and_binary "$PID" "$FULL_EX"; then
            continue
        fi

        RDB_PATH=$(discover_redis_rdb_database "$HOST" "$PORT" "")
        COMMANDS=$(discover_redis_available_commands "$HOST" "$PORT" "")
        SLAVES=$(discover_redis_available_slaves "$HOST" "$PORT" "")

        if [[ -n "$INSTANCE" ]]; then
            if [[ "$DISCOVERY_TYPE" == "general" ]]; then
                generate_redis_stats_report "$HOST" "$PORT" ""
                generate_general_discovery_json "$HOST" "$PORT" "$INSTANCE" "$RDB_PATH" "$INSTANCE_PROCESS_NAME" "$INSTANCE_PROCESS_PATH"
            elif [[ "$DISCOVERY_TYPE" == "stats" ]]; then
                for COMMAND in ${COMMANDS}; do
                    generate_commands_discovery_json "$HOST" "$PORT" "$COMMAND" "$INSTANCE"
                done
            elif [[ "$DISCOVERY_TYPE" == "replication" ]]; then
                for SLAVE in ${SLAVES}; do
                    generate_replication_discovery_json "$HOST" "$PORT" "$SLAVE" "$INSTANCE"
                done
            fi
        fi
    fi
done | sed -e 's:},$:\}:'
echo -n ']}'
echo ''
unset IFS
