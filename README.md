# Redis Template for Zabbix

<img width="800" alt="Redis General View" src="https://github.com/pavelnemirovsky/zabbix-redis-template/blob/master/images/redis_general.png?raw=true">

<img width="800" alt="Dashboard" src="https://github.com/pavelnemirovsky/zabbix-redis-template/blob/master/images/redis_command.png?raw=true">


## Table of Contents
- [Features](#features)
- [Installation](#installation)
- [Installation (Optional)](#installation-optional)
- [Important](#important)
- [Plans](#plans)
- [Discovery Flow ](#example-instance-discovery)
- [Discovery Examples ](#example-commands-stats-discovery)

## Features
  - Ability to discovery multiple Redis instances running on same host
  - Generate automatically a zabbix screen for general overview and Redis commands are currently in use only!
  - Triggers identify command anomaly (not done yet) and instance crash

## Installation
  - Import **zbx_template/zbx_export_templates.xml** via **Zabbix -> Configuration -> Templates -> Import**
  - Place **zbx_template/zbx_redis_discovery.sh** under **/usr/bin/zbx_redis_discovery.sh**
  - Place template userparameters under **/etc/zabbix/zabbix_agentd.d/** or other place according your installation
  - Restart your zabbix agent where all above were placed

## Installation (OPTIONAL)
  - Replace following line **<host>your.first.redis.host.local</host>** under **zbx_screens/zbx_export_screens.xml** with your first redis host
  - Import saved file zbx_export_screens.xml via **Zabbix -> Monitoring -> Screens**

## Important
  - Make sure your redis-server configuration file ends with **.conf** otherwise INSTANCE name won't be discovered
  - Discovery produce stats files from where template gathers stats per 1 min basis, so important to leave discovery rules to run with short interval only. (current template do that each 1 min)
  - You don't have to worry about discovery process to update all items per 1 min basic, actually Zabbix Server use its own cache and perform DB update only when there is a new item appears.

## Plans
  - Keep pushing on Zabbix R&D to let create graphs with multiple prototype items, meanwhile use [Zabbix Grafana](https://github.com/alexanderzobnin/grafana-zabbix)

Discovery with Statistics Report Flow
===========================

![Discovery](https://www.websequencediagrams.com/cgi-bin/cdraw?lz=dGl0bGUgUmVkaXMgRGlzY292ZXJ5IEZsb3cgJiBTdGF0aXN0aWNzIFJlcG9ydCBHZW5lcmF0b3IKClphYmJpeCBTZXJ2ZXJzLT4ACQdBZ2VudDogcmVkaXMuZABKCFtnADQFbCx7JFJFRElTX1BBU1NXT1JEU31dABsvc3RhdHMANBQJAGQvcmVwbGljYXRpb24AOxUAgVoJAIFOBS0-AIFEDy5zaACBVhEuc2gKCmxvb3AgdmlhIGxpc3Qgb2YgaW5zdGFuY2VzCgAxEi0-AIJ3BTogAIIjCF8AgjUFXwAsCCgAgjEIIDxQYXNzd29yZHMgQXJyYXk-KQpGaWxlc3lzdGVtLT4AgxsGOi90bXAvAIJ4BS0kSE9TVC0kUE9SVAABKVQtc2xvd2xvZy1sZW4AAzNyYXcAQSttYXhjbGllbnQAgW4sYXZhbGFibGVfY29tbWFuZHMoAIQMBgCCDRQAIzNzbGF2ZXMoAIQSCwCCZhVlbmQKAIYxBQCEAhYAhWkGdGVfAIVxB18AhgEJX2pzb24oKQAYJQCBWggACDYAhVULAG0SAIR2FACHNA4AgSQOX3Jlc3BvbnNlAIYGDwCHeA4AHBoK&s=modern-blue)

Example Instance Discovery:
===========================

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

Example Commands Stats Discovery:
=================================
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
