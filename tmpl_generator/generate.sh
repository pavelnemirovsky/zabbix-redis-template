#!/bin/bash

REDIS_CALLS=$(cat redis_calls.list)
REDIS_USEC_CALL=$(cat redis_usec.list)

for v in $REDIS_CALLS; do
    echo "
    <item_prototype>
        <name>Redis: &quot;{#INSTANCE}&quot; - &quot;$1&quot;</name>
        <type>0</type>
        <snmp_community/>
        <multiplier>0</multiplier>
        <snmp_oid/>
        <key>redis.stat[&quot;$v&quot;,{#HOST},{#PORT}]</key>
        <delay>300</delay>
        <history>90</history>
        <trends>365</trends>
        <status>0</status>
        <value_type>0</value_type>
        <allowed_hosts/>
        <units/>
        <delta>1</delta>
        <snmpv3_contextname/>
        <snmpv3_securityname/>
        <snmpv3_securitylevel>0</snmpv3_securitylevel>
        <snmpv3_authprotocol>0</snmpv3_authprotocol>
        <snmpv3_authpassphrase/>
        <snmpv3_privprotocol>0</snmpv3_privprotocol>
        <snmpv3_privpassphrase/>
        <formula>1</formula>
        <delay_flex/>
        <params/>
        <ipmi_sensor/>
        <data_type>0</data_type>
        <authtype>0</authtype>
        <username/>
        <password/>
        <publickey/>
        <privatekey/>
        <port/>
        <description/>
        <inventory_link>0</inventory_link>
        <applications/>
        <valuemap/>
        <logtimefmt/>
        <application_prototypes>
            <application_prototype>
                <name>Redis: {#INSTANCE} - Command Statistics</name>
            </application_prototype>
        </application_prototypes>
    </item_prototype>
    "
done

for v in $REDIS_USEC_CALL; do
    echo "
    <item_prototype>
        <name>Redis: &quot;{#INSTANCE}&quot; - &quot;$1&quot;</name>
        <type>0</type>
        <snmp_community/>
        <multiplier>0</multiplier>
        <snmp_oid/>
        <key>redis.stat[&quot;$v&quot;,{#HOST},{#PORT}]</key>
        <delay>300</delay>
        <history>90</history>
        <trends>365</trends>
        <status>0</status>
        <value_type>0</value_type>
        <allowed_hosts/>
        <units/>
        <delta>2</delta>
        <snmpv3_contextname/>
        <snmpv3_securityname/>
        <snmpv3_securitylevel>0</snmpv3_securitylevel>
        <snmpv3_authprotocol>0</snmpv3_authprotocol>
        <snmpv3_authpassphrase/>
        <snmpv3_privprotocol>0</snmpv3_privprotocol>
        <snmpv3_privpassphrase/>
        <formula>1</formula>
        <delay_flex/>
        <params/>
        <ipmi_sensor/>
        <data_type>0</data_type>
        <authtype>0</authtype>
        <username/>
        <password/>
        <publickey/>
        <privatekey/>
        <port/>
        <description/>
        <inventory_link>0</inventory_link>
        <applications/>
        <valuemap/>
        <logtimefmt/>
        <application_prototypes>
            <application_prototype>
                <name>Redis: {#INSTANCE} - Command Statistics</name>
            </application_prototype>
        </application_prototypes>
    </item_prototype>
    "
done
