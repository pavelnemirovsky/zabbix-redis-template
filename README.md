# Redis Template for Zabbix (Redis OSS, KeyDB, Valkey)

<img width="800" alt="Redis General View" src="https://github.com/pavelnemirovsky/zabbix-redis-template/blob/master/images/redis_general.png?raw=true">

<img width="800" alt="Dashboard" src="https://github.com/pavelnemirovsky/zabbix-redis-template/blob/master/images/redis_command.png?raw=true">


## Table of contents
- [Features](#features)
- [Compatibility](#compatibility)
- [Installation](#installation)
- [Installation (optional)](#installation-optional)
- [Important](#important)
- [Debugging / issue reporting](#debugging-issue-reporting)
- [Plans](#plans)
- [Discovery flow and LLD examples](#discovery-flow-and-lld-examples)
  - [Example: instance discovery](#example-instance-discovery)
  - [Example: command stats discovery](#example-command-stats-discovery)
  - [Example: replication discovery](#example-replication-discovery)

## Features
  - Discover multiple instances on one host: **`redis-server`**, **`keydb-server`**, **`valkey-server`**. The discovery script picks **`redis-cli`**, **`keydb-cli`**, or **`valkey-cli`** by process when that binary is installed; otherwise it uses **`redis-cli`** (RESP-compatible fallback)
  - **Screens:** **v3** and **v4** template imports include screens in the same file; **v6** is template-only—add **`zbx_templates_and_screens/zbx_export_screens_v3.xml`** if you want those screen layouts ([Compatibility](#compatibility))
  - Triggers identify command anomaly (not done yet) and instance crash

## Compatibility

This project targets **Zabbix server and proxies from 3.0 through 7.x** and any **Redis-compatible** server that speaks the Redis wire protocol and exposes the usual **`INFO` / `CONFIG` / `SLOWLOG`** commands (**Redis OSS**, **KeyDB**, **Valkey**). Discovery uses each vendor’s CLI when present: **`redis-cli`** for **`redis-server`**, **`keydb-cli`** (else baseline) for **`keydb-server`**, **`valkey-cli`** (else baseline) for **`valkey-server`**. The agent needs **at least one** of **`redis-cli`**, **`keydb-cli`**, or **`valkey-cli`** (baseline prefers Redis, then KeyDB, then Valkey). Use a **Zabbix agent** whose major version matches your server (classic **zabbix_agentd** with `UserParameter` definitions matches the shipped **zabbix_agentd.d** snippets).

**Which template to import** (**Configuration → Templates → Import**; XML and JSON are equivalent):

| Your Zabbix version | Files in `zbx_templates_and_screens/` |
| --- | --- |
| **5.x, 6.x, 7.x** | **`zbx_export_templates_v6.xml`** or **`zbx_export_templates_v6.json`** — same template, **6.4** export schema (UUIDs, `template_groups`), maintained for **5.4+ through 7.x** |
| **4.x** | **`zbx_export_templates_v4.xml`** (4.2 export) |
| **3.x** | **`zbx_export_templates_v3.xml`** |

**Screens:** The **v3** and **v4** template archives above include **screens** in the same file—one import adds both the template and its dashboard screens. The **v6** export (**`zbx_export_templates_v6.xml`** / **`.json`**) is **template only**; use the separate **`zbx_export_screens_v3.xml`** (see [Installation (optional)](#installation-optional)) if you want those screen layouts.

If a **5.x** server refuses a **6.4**-format import, use **`zbx_export_templates_v4.xml`** instead (older schema that 5.x importers accept), or import **v6** on a **6.x / 7.x** instance and re-export from there after upgrade.

Further detail: **`docs/ZABBIX_TEMPLATE.md`**.

## Installation
  - Import the template that matches your Zabbix version (see [Compatibility](#compatibility)) via **Zabbix → Configuration → Templates → Import**
  - Copy **zabbix_agentd.d/zbx_redis_discovery.sh** to **/usr/bin/zbx_redis_discovery.sh** (or keep the path aligned with your **UserParameter** definitions). On the agent, install **at least one** of **`redis-cli`**, **`keydb-cli`**, or **`valkey-cli`** (discovery resolves baseline in that preference order). Prefer vendor CLIs for **`keydb-server`** / **`valkey-server`** when installed. **User parameters** in **`zbx_userparameters_redis.conf`** still call **`redis-cli`** for some items—install **`redis-cli`** too if you rely on those checks on a KeyDB/Valkey-only host, or adjust the config.
  - Copy **zabbix_agentd.d/zbx_userparameters_redis.conf** into **/etc/zabbix/zabbix_agentd.d/** (or the directory your agent uses for includes)
  - Restart the Zabbix agent on hosts where you installed the script and user parameters

## Installation (OPTIONAL)
  - Replace every `<host>your.first.redis.host.local</host>` in **zbx_templates_and_screens/zbx_export_screens_v3.xml** with the hostname of the first Redis host you monitor in Zabbix (as shown under **Configuration -> Hosts**)
  - Import **zbx_export_screens_v3.xml** via **Zabbix -> Monitoring -> Screens**

## Important
  - Make sure your redis-server configuration file ends with **.conf** otherwise INSTANCE name won't be discovered
  - Discovery produce stats files from where template gathers stats per 1 min basis, so important to leave discovery rules to run with short interval only. (current template do that each 1 min)
  - You don't have to worry about discovery process to update all items per 1 min basic, actually Zabbix Server use its own cache and perform DB update only when there is a new item appears.

## Debugging / Issue reporting
  - If **Discover Redis Instances** fails, run **`/usr/bin/zbx_redis_discovery.sh general debug`** (or the same path you configured on the agent) and attach the output to the issue
  - If **Discover Redis Commands** fails: **`/usr/bin/zbx_redis_discovery.sh stats debug`**
  - If **Discover Redis Slaves** fails: **`/usr/bin/zbx_redis_discovery.sh replication debug`**

## Plans

- Encourage upstream Zabbix support for **graphs that combine multiple LLD prototype metrics** in a single view (today’s UI is awkward for that). Until it lands, **[Grafana with the Zabbix plugin](https://github.com/alexanderzobnin/grafana-zabbix)** remains the most practical way to build those multi-series dashboards.

## Discovery flow and LLD examples

<img width="800" alt="Discovery Flow" src="https://github.com/pavelnemirovsky/zabbix-redis-template/blob/master/images/redis_discovery_flow.png?raw=true">

**`zabbix_get` is normally run on your Zabbix server or on a Zabbix proxy** (the component that reaches the agent over TCP 10050), not on the monitored Redis host. The `-s` argument is the **agent host** as configured in Zabbix (DNS or IP). To test directly on the machine where Redis runs, call the discovery script or use `zabbix_agentd -t` there instead.

### Example: instance discovery

```json
zabbix_get -s redis.host.me -k redis.discovery[general,"123456 123456"] | jq .
{
  "data": [
    {
      "{#HOST}": "127.0.0.1",
      "{#PORT}": "6399",
      "{#INSTANCE}": "INSTANCE1",
      "{#RDB_PATH}": "/usr/share/redis/instance1.rdb"
    },
    {
      "{#HOST}": "127.0.0.1",
      "{#PORT}": "6395",
      "{#INSTANCE}": "INSTANCE2",
      "{#RDB_PATH}": "/usr/share/redis/instance2.rdb"
    },
    {
      "{#HOST}": "127.0.0.1",
      "{#PORT}": "6397",
      "{#INSTANCE}": "INSTANCE3",
      "{#RDB_PATH}": "/usr/share/redis/instance3.rdb"
    },
    {
      "{#HOST}": "127.0.0.1",
      "{#PORT}": "6389",
      "{#INSTANCE}": "INSTANCE4",
      "{#RDB_PATH}": "/usr/share/redis/instance4.rdb"
    }
  ]
}
```

### Example: command stats discovery
```json
zabbix_get -s redis.host.me -k redis.discovery[stats,"123456 123456"] | jq .
{
  "data": [
    {
      "{#HOST}": "127.0.0.1",
      "{#PORT}": "6399",
      "{#COMMAND}": "cmdstat_auth",
      "{#INSTANCE}": "INSTANCE1"
    },
    {
      "{#HOST}": "127.0.0.1",
      "{#PORT}": "6399",
      "{#COMMAND}": "cmdstat_ping",
      "{#INSTANCE}": "INSTANCE1"
    },
    {
      "{#HOST}": "127.0.0.1",
      "{#PORT}": "6399",
      "{#COMMAND}": "cmdstat_info",
      "{#INSTANCE}": "INSTANCE1"
    },
    {
      "{#HOST}": "127.0.0.1",
      "{#PORT}": "6399",
      "{#COMMAND}": "cmdstat_config",
      "{#INSTANCE}": "INSTANCE1"
    },
    {
      "{#HOST}": "127.0.0.1",
      "{#PORT}": "6399",
      "{#COMMAND}": "cmdstat_slowlog",
      "{#INSTANCE}": "INSTANCE1"
    },
    {
      "{#HOST}": "127.0.0.1",
      "{#PORT}": "6395",
      "{#COMMAND}": "cmdstat_auth",
      "{#INSTANCE}": "INSTANCE2"
    },
    {
      "{#HOST}": "127.0.0.1",
      "{#PORT}": "6395",
      "{#COMMAND}": "cmdstat_ping",
      "{#INSTANCE}": "INSTANCE2"
    },
    {
      "{#HOST}": "127.0.0.1",
      "{#PORT}": "6395",
      "{#COMMAND}": "cmdstat_info",
      "{#INSTANCE}": "INSTANCE2"
    },
    {
      "{#HOST}": "127.0.0.1",
      "{#PORT}": "6395",
      "{#COMMAND}": "cmdstat_config",
      "{#INSTANCE}": "INSTANCE2"
    },
    {
      "{#HOST}": "127.0.0.1",
      "{#PORT}": "6395",
      "{#COMMAND}": "cmdstat_slowlog",
      "{#INSTANCE}": "INSTANCE2"
    },
    {
      "{#HOST}": "127.0.0.1",
      "{#PORT}": "6397",
      "{#COMMAND}": "cmdstat_set",
      "{#INSTANCE}": "INSTANCE3"
    },
    {
      "{#HOST}": "127.0.0.1",
      "{#PORT}": "6397",
      "{#COMMAND}": "cmdstat_select",
      "{#INSTANCE}": "INSTANCE3"
    },
    {
      "{#HOST}": "127.0.0.1",
      "{#PORT}": "6397",
      "{#COMMAND}": "cmdstat_auth",
      "{#INSTANCE}": "INSTANCE3"
    },
    {
      "{#HOST}": "127.0.0.1",
      "{#PORT}": "6397",
      "{#COMMAND}": "cmdstat_ping",
      "{#INSTANCE}": "INSTANCE3"
    },
    {
      "{#HOST}": "127.0.0.1",
      "{#PORT}": "6397",
      "{#COMMAND}": "cmdstat_info",
      "{#INSTANCE}": "INSTANCE3"
    },
    {
      "{#HOST}": "127.0.0.1",
      "{#PORT}": "6397",
      "{#COMMAND}": "cmdstat_config",
      "{#INSTANCE}": "INSTANCE3"
    },
    {
      "{#HOST}": "127.0.0.1",
      "{#PORT}": "6397",
      "{#COMMAND}": "cmdstat_slowlog",
      "{#INSTANCE}": "INSTANCE3"
    },
    {
      "{#HOST}": "127.0.0.1",
      "{#PORT}": "6389",
      "{#COMMAND}": "cmdstat_auth",
      "{#INSTANCE}": "INSTANCE4"
    },
    {
      "{#HOST}": "127.0.0.1",
      "{#PORT}": "6389",
      "{#COMMAND}": "cmdstat_ping",
      "{#INSTANCE}": "INSTANCE4"
    },
    {
      "{#HOST}": "127.0.0.1",
      "{#PORT}": "6389",
      "{#COMMAND}": "cmdstat_info",
      "{#INSTANCE}": "INSTANCE4"
    },
    {
      "{#HOST}": "127.0.0.1",
      "{#PORT}": "6389",
      "{#COMMAND}": "cmdstat_config",
      "{#INSTANCE}": "INSTANCE4"
    },
    {
      "{#HOST}": "127.0.0.1",
      "{#PORT}": "6389",
      "{#COMMAND}": "cmdstat_slowlog",
      "{#INSTANCE}": "INSTANCE4"
    }
  ]
}
```

### Example: replication discovery
```json
zabbix_get -s redis.host.me -k redis.discovery[replication] | jq .
{
  "data": [
    {
      "{#HOST}": "127.0.0.1",
      "{#PORT}": "6400",
      "{#SLAVE}": "slave0",
      "{#INSTANCE}": "INSTANCE1"
    },
    {
      "{#HOST}": "127.0.0.1",
      "{#PORT}": "6400",
      "{#SLAVE}": "slave1",
      "{#INSTANCE}": "INSTANCE1"
    },
    {
      "{#HOST}": "127.0.0.1",
      "{#PORT}": "6400",
      "{#SLAVE}": "slave2",
      "{#INSTANCE}": "INSTANCE1"
    },
    {
      "{#HOST}": "127.0.0.1",
      "{#PORT}": "6400",
      "{#SLAVE}": "slave4",
      "{#INSTANCE}": "INSTANCE1"
    },
    {
      "{#HOST}": "127.0.0.1",
      "{#PORT}": "6400",
      "{#SLAVE}": "slave5",
      "{#INSTANCE}": "INSTANCE1"
    }
  ]
}
```
