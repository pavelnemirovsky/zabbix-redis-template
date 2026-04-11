#!/usr/bin/env bash
# Zabbix LLD helper for Redis-compatible servers (Redis OSS, KeyDB, Valkey): discovers instances
# from ps(1), probes with the vendor CLI when installed (redis-cli / keydb-cli / valkey-cli), and
# optionally validates OS process + server-reported executable to reduce false positives.

set -o pipefail 2>/dev/null || true
set -o noglob 2>/dev/null || true
setopt noglob &>/dev/null || true

# Locale: set once and export so every child (ps, grep, redis-cli, awk, sed) inherits it.
# Avoids repeated locale initialization and UTF-8 collation cost; keeps tool output stable for parsing.
export LC_ALL=C
export LANGUAGE=C

REDIS_CLI_DEFAULT_PATH="/usr/bin/redis-cli"
KEYDB_CLI_DEFAULT_PATH="/usr/bin/keydb-cli"
VALKEY_CLI_DEFAULT_PATH="/usr/bin/valkey-cli"

# Extra search paths when redis-cli is not on PATH (Zabbix agent often has a minimal environment).
REDIS_CLI_SEARCH_PATHS=(
    "$REDIS_CLI_DEFAULT_PATH"
    "/usr/local/bin/redis-cli"
    "/opt/homebrew/bin/redis-cli"
    "/opt/redis/bin/redis-cli"
    "/snap/bin/redis-cli"
)

# If a *-server process runs from an absolute path, sibling redis-cli may live in the same bin dir.
try_redis_cli_beside_running_server() {
    local word dir
    while read -r line; do
        for word in $line; do
            [[ "$word" != /* ]] && continue
            case "$word" in
                *redis-server | *keydb-server | *valkey-server) ;;
                *) continue ;;
            esac
            dir=$(dirname "$word")
            [[ -n "$dir" && -x "$dir/redis-cli" ]] && {
                echo "$dir/redis-cli"
                return 0
            }
        done
    done < <(ps -eo args 2>/dev/null | grep -E '[Rr]edis-server|[Kk]eydb-server|[Vv]alkey-server' || true)
    return 1
}

# Print first usable path for baseline client (redis-cli, else keydb/valkey), or nothing.
# Honors /tmp/redis-cli only when it points to an existing executable file.
resolve_baseline_redis_family_cli() {
    local c="" p

    if [[ -e /tmp/redis-cli ]]; then
        c=$(head -n 1 /tmp/redis-cli | tr -d '\r\n')
        if [[ -n "$c" ]] && [[ -f "$c" || -L "$c" ]] && [[ -x "$c" ]]; then
            echo "$c"
            return 0
        fi
    fi

    if command -v locate &>/dev/null; then
        c=$(locate redis-cli 2>/dev/null | grep -E '(^|/)redis-cli$' | head -n 1)
        [[ -n "$c" && -x "$c" ]] && {
            echo "$c"
            return 0
        }
    fi

    p=$(command -v redis-cli 2>/dev/null)
    [[ -z "$p" ]] && p=$(type -P redis-cli 2>/dev/null)
    [[ -n "$p" && -x "$p" ]] && {
        echo "$p"
        return 0
    }

    if command -v which &>/dev/null; then
        p=$(which redis-cli 2>/dev/null)
        [[ -n "$p" && -x "$p" ]] && {
            echo "$p"
            return 0
        }
    fi

    for p in "${REDIS_CLI_SEARCH_PATHS[@]}"; do
        [[ -x "$p" ]] && {
            echo "$p"
            return 0
        }
    done

    c=$(try_redis_cli_beside_running_server) || true
    [[ -n "$c" && -x "$c" ]] && {
        echo "$c"
        return 0
    }

    if command -v keydb-cli &>/dev/null; then
        p=$(command -v keydb-cli)
        [[ -x "$p" ]] && {
            echo "$p"
            return 0
        }
    fi
    [[ -x "$KEYDB_CLI_DEFAULT_PATH" ]] && {
        echo "$KEYDB_CLI_DEFAULT_PATH"
        return 0
    }

    if command -v valkey-cli &>/dev/null; then
        p=$(command -v valkey-cli)
        [[ -x "$p" ]] && {
            echo "$p"
            return 0
        }
    fi
    [[ -x "$VALKEY_CLI_DEFAULT_PATH" ]] && {
        echo "$VALKEY_CLI_DEFAULT_PATH"
        return 0
    }

    return 1
}

# CLI vs server: all three speak RESP; PING / INFO / CONFIG GET / SLOWLOG work the same.
# Per ps(1) line: redis-server -> redis-cli; keydb-server -> keydb-cli if present else redis-cli;
# valkey-server -> valkey-cli if present else redis-cli.

# Parse "pid args" from ps -eo pid,args (no colon mangling; paths/usernames cannot break fields).
# Picks bind address as last host:port token, or host + port as two words, or --port N.
extract_pid_host_port() {
    local line="$1"
    local pid="" host="" port="" rest hp last2

    [[ -z "$line" ]] && {
        printf '\t\t\n'
        return
    }

    pid=$(awk '{print $1}' <<<"$line")
    [[ "$pid" =~ ^[0-9]+$ ]] || pid=""
    rest=$(awk '{$1=""; sub(/^ /,""); print}' <<<"$line")

    hp=$(echo "$rest" | grep -oE '(\*|127\.0\.0\.1|localhost|[0-9]{1,3}(\.[0-9]{1,3}){3}):[0-9]{2,5}' | tail -n 1)
    if [[ -n "$hp" ]]; then
        host=${hp%%:*}
        [[ "$host" == '*' ]] && host='127.0.0.1'
        port=${hp##*:}
    fi

    if [[ -z "$port" ]] && echo "$rest" | grep -qE '[[:space:]]--port[[:space:]]'; then
        port=$(echo "$rest" | sed -n 's/.*--port[[:space:]]\{1,\}\([0-9][0-9]*\).*/\1/p' | head -n 1)
        [[ -n "$port" ]] && host="127.0.0.1"
    fi

    # Two-token bind: ... redis-server 127.0.0.1 6379
    if [[ -z "$port" ]]; then
        last2=$(echo "$rest" | awk '{print $(NF-1), $NF}')
        if [[ "$last2" =~ ^([^[:space:]]+)[[:space:]]+([0-9]{2,5})$ ]]; then
            host=${BASH_REMATCH[1]}
            port=${BASH_REMATCH[2]}
            [[ "$host" == '*' ]] && host='127.0.0.1'
        fi
    fi

    printf '%s\t%s\t%s\n' "$pid" "${host:-}" "${port:-}"
}

# Second line of redis-cli "CONFIG GET <key>" output is the value. Plain format is one field
# (/var/lib/redis); pretty format is "2) \"/var/lib/redis\"" — awk '{print $2}' misses the plain case.
parse_redis_config_get_value() {
    awk 'NR==2{
        line=$0
        sub(/^[0-9]+\)[[:space:]]+/, "", line)
        gsub(/^"|"$/, "", line)
        sub(/\r$/, "", line)
        print line
    }'
}

usage() {
    cat <<'EOF'
Usage: zbx_redis_discovery.sh <general|stats|replication> [password ...] [debug]

  general|stats|replication   LLD mode (JSON for Zabbix; general also writes /tmp/redis-* caches)
  password                    optional; tried in order until PONG
  debug                       enables set -x
  -h|--help|help              this text + clients, [V]/[X] per flavor (ps), per-instance CLI ok

Requires at least one client: redis-cli, keydb-cli, or valkey-cli (resolve order: redis → keydb → valkey;
first hit cached in /tmp/redis-cli). Vendor CLI is chosen per ps line (redis/keydb/valkey-server).

Exit: 0 → JSON on stdout; 1 → bad args or no client binary.
EOF
}

# After --help: client paths + same instance rows LLD would read from ps (no live probe).
# [V] = seen / usable; [X] = not seen or no executable CLI for that row.
help_show_local_inventory() {
    local r="" k="" v="" _list s flavor pid host port cli OIFS row_ok fr fk fv rx kx vx

    r=$(resolve_baseline_redis_family_cli) || r=""
    command -v keydb-cli &>/dev/null && k=$(command -v keydb-cli)
    [[ -z "$k" ]] && [[ -x "$KEYDB_CLI_DEFAULT_PATH" ]] && k="$KEYDB_CLI_DEFAULT_PATH"
    command -v valkey-cli &>/dev/null && v=$(command -v valkey-cli)
    [[ -z "$v" ]] && [[ -x "$VALKEY_CLI_DEFAULT_PATH" ]] && v="$VALKEY_CLI_DEFAULT_PATH"

    echo ""
    echo "Clients: redis-cli=${r:--}  keydb-cli=${k:--}  valkey-cli=${v:--}"

    _list=$(
        ps -eo pid,args 2>/dev/null | grep -v grep | grep -E -i 'keydb-server|redis-server|valkey-server'
    )

    fr=0
    fk=0
    fv=0
    if [[ -n "$_list" ]]; then
        echo "$_list" | grep -qF 'redis-server' && fr=1
        echo "$_list" | grep -qF 'keydb-server' && fk=1
        echo "$_list" | grep -qF 'valkey-server' && fv=1
    fi
    rx='[X]'
    kx='[X]'
    vx='[X]'
    [[ "$fr" -eq 1 ]] && rx='[V]'
    [[ "$fk" -eq 1 ]] && kx='[V]'
    [[ "$fv" -eq 1 ]] && vx='[V]'
    echo "Flavors discovered (ps):  $rx redis  $kx keydb  $vx valkey"

    echo "Instances ([V]=CLI ok / [X]=bad CLI; rows need pid + host:port in argv; config-only daemons omitted):"
    if [[ -z "$_list" ]]; then
        echo "  (none — no redis-server / keydb-server / valkey-server)"
        return
    fi

    OIFS=$IFS
    IFS=$'\n'
    for s in $_list; do
        [[ -z "$s" ]] && continue
        if echo "$s" | grep -qi 'valkey-server'; then
            flavor=valkey
            cli="${v:-$r}"
        elif echo "$s" | grep -qi 'keydb-server'; then
            flavor=keydb
            cli="${k:-$r}"
        else
            flavor=redis
            cli="$r"
        fi
        IFS=$'\t' read -r pid host port <<<"$(extract_pid_host_port "$s")"
        [[ -z "$host" || -z "$port" || ! "$pid" =~ ^[0-9]+$ ]] && continue
        row_ok='[X]'
        if [[ -n "$cli" && "$cli" != "-" && -x "$cli" ]]; then
            row_ok='[V]'
        fi
        printf '  %s  %-6s  %s:%s  pid=%s  cli=%s\n' "$row_ok" "$flavor" "$host" "$port" "$pid" "${cli:--}"
    done
    IFS=$OIFS
}

ARGS=("$@")
DISCOVERY_TYPE=""
PASSWORDS=()
DEBUG=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help|help)
            usage
            help_show_local_inventory
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
    ps -eo pid,args 2>/dev/null | grep -v grep | grep -E -i 'keydb-server|redis-server|valkey-server'
)

# REQUIRED: at least one RESP client. REDIS_CLI holds the baseline (see resolve_baseline_redis_family_cli).
if ! REDIS_CLI=$(resolve_baseline_redis_family_cli); then
    echo '{"data":[]}'
    exit 1
fi
echo "$REDIS_CLI" >/tmp/redis-cli

if [[ ! -f "$REDIS_CLI" ]] && [[ ! -x "$REDIS_CLI" ]]; then
    echo '{"data":[]}'
    exit 1
fi

# Per-flavor CLIs for ACTIVE_CLI (KeyDB / Valkey); baseline REDIS_CLI may already be any vendor.
KEYDB_CLI=""
if command -v keydb-cli &>/dev/null; then
    KEYDB_CLI=$(command -v keydb-cli)
elif [[ -x "$KEYDB_CLI_DEFAULT_PATH" ]]; then
    KEYDB_CLI="$KEYDB_CLI_DEFAULT_PATH"
fi

VALKEY_CLI=""
if command -v valkey-cli &>/dev/null; then
    VALKEY_CLI=$(command -v valkey-cli)
elif [[ -x "$VALKEY_CLI_DEFAULT_PATH" ]]; then
    VALKEY_CLI="$VALKEY_CLI_DEFAULT_PATH"
fi

# Active client binary for the current ps(1) line (set in main loop).
ACTIVE_CLI="$REDIS_CLI"

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

    ALIVE=$($ACTIVE_CLI -h "$HOST" -p "$PORT" ${PASSWORD:+-a "$PASSWORD"} ping 2>/dev/null)

    if [[ "$ALIVE" != "PONG" ]]; then
        return 1
    fi

    INSTANCE=$($ACTIVE_CLI -h "$HOST" -p "$PORT" ${PASSWORD:+-a "$PASSWORD"} info 2>/dev/null | grep '^config_file:' | cut -d: -f2- | sed 's/\r$//' | sed 's/.conf$//' | rev | cut -d/ -f1 | rev | tr -d '[:space:]' | tr '[:lower:]' '[:upper:]')
    if [[ -z "$INSTANCE" ]]; then
        INSTANCE="${HOST}:${PORT}"
    fi

    FULL_PROCESS=$($ACTIVE_CLI -h "$HOST" -p "$PORT" ${PASSWORD:+-a "$PASSWORD"} info 2>/dev/null | grep '^executable:' | cut -d: -f2- | sed 's/\r$//' | tr -d '[:space:]')

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

    ALIVE=$($ACTIVE_CLI -h "$HOST" -p "$PORT" ${PASSWORD:+-a "$PASSWORD"} ping 2>/dev/null)

    if [[ "$ALIVE" != "PONG" ]]; then
        return 1
    fi

    INSTANCE_RDB_PATH=$($ACTIVE_CLI -h "$HOST" -p "$PORT" ${PASSWORD:+-a "$PASSWORD"} config get "dir" 2>/dev/null | parse_redis_config_get_value)
    INSTANCE_RDB_FILE=$($ACTIVE_CLI -h "$HOST" -p "$PORT" ${PASSWORD:+-a "$PASSWORD"} config get "dbfilename" 2>/dev/null | parse_redis_config_get_value)

    echo "${INSTANCE_RDB_PATH}/${INSTANCE_RDB_FILE}"
}

discover_redis_available_commands() {
    local HOST="$1"
    local PORT="$2"
    local PASSWORD="$3"
    local ALIVE REDIS_COMMANDS

    ALIVE=$($ACTIVE_CLI -h "$HOST" -p "$PORT" ${PASSWORD:+-a "$PASSWORD"} ping 2>/dev/null)

    if [[ "$ALIVE" != "PONG" ]]; then
        return 1
    fi

    REDIS_COMMANDS=$($ACTIVE_CLI -h "$HOST" -p "$PORT" ${PASSWORD:+-a "$PASSWORD"} info all 2>/dev/null | grep cmdstat | cut -d: -f1)

    (IFS=$'\n'; echo "${REDIS_COMMANDS[*]}")
}

discover_redis_available_slaves() {
    local HOST="$1"
    local PORT="$2"
    local PASSWORD="$3"
    local ALIVE REDIS_SLAVES

    ALIVE=$($ACTIVE_CLI -h "$HOST" -p "$PORT" ${PASSWORD:+-a "$PASSWORD"} ping 2>/dev/null)

    if [[ "$ALIVE" != "PONG" ]]; then
        return 1
    fi

    REDIS_SLAVES=$($ACTIVE_CLI -h "$HOST" -p "$PORT" ${PASSWORD:+-a "$PASSWORD"} info replication 2>/dev/null | grep -E '^slave[0-9]+:' | cut -d: -f1)

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

    $ACTIVE_CLI -h "$HOST" -p "$PORT" ${PASSWORD:+-a "$PASSWORD"} info all 2>/dev/null >"$REDIS_REPORT_RESULT_TMP"
    local REDIS_REPORT_RC=$?

    $ACTIVE_CLI -h "$HOST" -p "$PORT" ${PASSWORD:+-a "$PASSWORD"} slowlog len 2>/dev/null | awk '{print $2}' >"$REDIS_SLOWLOG_LEN_RESULT_TMP"
    local REDIS_SLOWLOG_LEN_RC=$?
    $ACTIVE_CLI -h "$HOST" -p "$PORT" ${PASSWORD:+-a "$PASSWORD"} slowlog reset 2>/dev/null >/dev/null || true

    $ACTIVE_CLI -h "$HOST" -p "$PORT" ${PASSWORD:+-a "$PASSWORD"} slowlog get 2>/dev/null >"$REDIS_SLOWLOG_RAW_RESULT_TMP"
    local REDIS_SLOWLOG_RAW_RC=$?

    $ACTIVE_CLI -h "$HOST" -p "$PORT" ${PASSWORD:+-a "$PASSWORD"} config get maxclients 2>/dev/null | parse_redis_config_get_value >"$REDIS_MAX_CLIENTS_RESULT_TMP"
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

    if echo "$s" | grep -qi 'valkey-server'; then
        ACTIVE_CLI="${VALKEY_CLI:-$REDIS_CLI}"
    elif echo "$s" | grep -qi 'keydb-server'; then
        ACTIVE_CLI="${KEYDB_CLI:-$REDIS_CLI}"
    else
        ACTIVE_CLI="$REDIS_CLI"
    fi

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
