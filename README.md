EMQ X Kafka Bridge
=============

## emqx_kafka_bridge.conf

``` properties
bridge.kafka.host = 127.0.0.1
bridge.kafka.port = 5672
bridge.kafka.partition_strategy = strict_round_robin
bridge.kafka.partition_workers = 8

bridge.kafka.auto_reconnect = 1
bridge.kafka.pool_size = 5

bridge.kafka.payload_encoding = json

bridge.kafka.rule.client.connect.1 = {"topic": "emqx.events.client_connect"}
bridge.kafka.rule.client.connack.1 = {"topic": "emqx.events.client_connack"}
bridge.kafka.rule.client.connected.1 = {"topic": "emqx.events.client_connected"}
bridge.kafka.rule.client.disconnected.1 = {"topic": "emqx.events.disconnected"}
bridge.kafka.rule.client.subscribe.1 = {"topic": "emqx.events.client_subscribe"}
bridge.kafka.rule.client.unsubscribe.1 = {"topic": "emqx.events.unsubscribe"}
bridge.kafka.rule.session.subscribed.1 = {"topic": "emqx.events.subscribed"}
bridge.kafka.rule.session.unsubscribed.1 = {"topic": "emqx.events.unsubscribed"}
bridge.kafka.rule.session.terminated.1 = {"topic": "emqx.events.terminated"}
bridge.kafka.rule.message.publish.1 = {"topic": "emqx.events.publish"}
bridge.kafka.rule.message.delivered.1 = {"topic": "emqx.events.delivered"}
bridge.kafka.rule.message.acked.1 = {"topic": "emqx.events.acked"}

```

API
----

* client.connected

``` json
{
    "action":"client_connected",
    "clientid":"C_1492410235117",
    "username":"C_1492410235117",
    "keepalive": 60,
    "ipaddress": "127.0.0.1",
    "proto_ver": 4,
    "connected_at": 1556176748,
    "conn_ack":0
}
```

* client.disconnected

``` json
{
    "action":"client_disconnected",
    "clientid":"C_1492410235117",
    "username":"C_1492410235117",
    "reason":"normal"
}
```

* client.subscribe

``` json
{
    "action":"client_subscribe",
    "clientid":"C_1492410235117",
    "username":"C_1492410235117",
    "topic":"world",
    "opts":{
        "qos":0
    }
}
```

* client.unsubscribe

``` json
{
    "action":"client_unsubscribe",
    "clientid":"C_1492410235117",
    "username":"C_1492410235117",
    "topic":"world"
}
```

* session.created

``` json
{
    "action":"session_created",
    "clientid":"C_1492410235117",
    "username":"C_1492410235117"
}
```

* session.subscribed

``` json
{
    "action":"session_subscribed",
    "clientid":"C_1492410235117",
    "username":"C_1492410235117",
    "topic":"world",
    "opts":{
        "qos":0
    }
}
```

* session.unsubscribed

``` json
{
    "action":"session_unsubscribed",
    "clientid":"C_1492410235117",
    "username":"C_1492410235117",
    "topic":"world"
}
```

* session.terminated

``` json
{
    "action":"session_terminated",
    "clientid":"C_1492410235117",
    "username":"C_1492410235117",
    "reason":"normal"
}
```

* message.publish

``` json
{
    "action":"message_publish",
    "from_client_id":"C_1492410235117",
    "from_username":"C_1492410235117",
    "topic":"world",
    "qos":0,
    "retain":true,
    "payload":"Hello world!",
    "ts":1492412774
}
```

* message.deliver

``` json
{
    "action":"message_delivered",
    "clientid":"C_1492410235117",
    "username":"C_1492410235117",
    "from_client_id":"C_1492410235117",
    "from_username":"C_1492410235117",
    "topic":"world",
    "qos":0,
    "retain":true,
    "payload":"Hello world!",
    "ts":1492412826
}
```

* message.acked

``` json
{
    "action":"message_acked",
    "clientid":"C_1492410235117",
    "username":"C_1492410235117",
    "from_client_id":"C_1492410235117",
    "from_username":"C_1492410235117",
    "topic":"world",
    "qos":1,
    "retain":true,
    "payload":"Hello world!",
    "ts":1492412914
}
```

参考
-------
修改自[emqx_web_hook](https://github.com/emqx/emqx-web-hook).

License
-------

Apache License Version 2.0
