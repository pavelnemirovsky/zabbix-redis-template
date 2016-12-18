Discovery sequence flow:
===========================

![Discovery Flow](https://www.websequencediagrams.com/cgi-bin/cdraw?lz=dGl0bGUgUmVkaXMgRGlzY292ZXJ5IEZsb3cKClphYmJpeCBTZXJ2ZXJzLT4ACQdBZ2VudDogcmVkaXMuZAAsCFtQYXNzd29yZHMgQXJyYXldADcIACoFLT4AIA8uc2gAMhEuc2gKI21haW4KABsSLT4AgR8FOiBHZXRMaXN0AIEtBUluc3RhbmNlcyg8AG8PPikKbG9vcCB2aWEgbGlzdCBvZiBpACYIAEMcAIFICF8AgVoFXwAsCCgpAHgcZ2VuZXJhdGUALgdzdGF0c19yZXBvcnQoKQplbmQKAIJcBQCBbxYANAkAgkIJX2pzb24AWxcAgnYOACIaAIJvDgCDPA4AWBwK&s=modern-blue)

Example Instance Discovery:
===========================

 ```
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
 ```
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
