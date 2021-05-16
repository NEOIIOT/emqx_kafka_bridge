%%--------------------------------------------------------------------
%% Copyright (c) 2020 EMQ Technologies Co., Ltd. All Rights Reserved.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%--------------------------------------------------------------------

%%
%% Modified from emqx_web_hook
%% Neo Tian.

-module(emqx_kafka_bridge).

-include("emqx_kafka_bridge.hrl").
-include("emqx.hrl").

-import(inet, [ntoa/1]).

%% APIs
-export([register_metrics/0, load/0, unload/0]).
%% Hooks callback
-export([on_client_connect/3, on_client_connack/4, on_client_connected/3,
         on_client_disconnected/4, on_client_subscribe/4, on_client_unsubscribe/4]).
-export([on_session_subscribed/4, on_session_unsubscribed/4, on_session_terminated/4]).
-export([on_message_publish/2, on_message_delivered/3, on_message_acked/3]).

%%--------------------------------------------------------------------
%% APIs
%%--------------------------------------------------------------------

register_metrics() ->
    lists:foreach(fun emqx_metrics:ensure/1,
                  ['kafka_bridge.client_connect',
                   'kafka_bridge.client_connack',
                   'kafka_bridge.client_connected',
                   'kafka_bridge.client_disconnected',
                   'kafka_bridge.client_subscribe',
                   'kafka_bridge.client_unsubscribe',
                   'kafka_bridge.session_subscribed',
                   'kafka_bridge.session_unsubscribed',
                   'kafka_bridge.session_terminated',
                   'kafka_bridge.message_publish',
                   'kafka_bridge.message_delivered',
                   'kafka_bridge.message_acked']).

load() ->
    io:format("Loading emqx_kafka_bridge plugin ~n"),
    {ok, _} = application:ensure_all_started(brod),
    {ok, BootstrapBroker} = application:get_env(?APP, broker),

    ok = brod:start_client(BootstrapBroker, brod_client_1),
    io:format("Init EMQX-Kafka-Bridge with ~p, ~n", [BootstrapBroker]),

    ets:new(topic_table, [named_table, protected, set, {keypos, 1}]),
    lists:foreach(fun({Hook, Filter}) ->
                     load_(Hook, Filter),
                     ok = brod:start_producer(brod_client_1, Filter, _ProducerConfig = []),
                     ets:insert(topic_table, {Hook, Filter})
                  end,
                  parse_rule(application:get_env(?APP, rules, []))),
    io:format("topic_table: ~p~n", [ets:tab2list(topic_table)]).

unload() ->
    lists:foreach(fun({Hook, _Filter}) -> unload_(Hook) end,
                  parse_rule(application:get_env(?APP, rules, []))).

%%--------------------------------------------------------------------
%% Client connect
%%--------------------------------------------------------------------

on_client_connect(ConnInfo =
                      #{clientid := ClientId,
                        username := Username,
                        peername := {Peerhost, _}},
                  _ConnProp,
                  _Env) ->
    emqx_metrics:inc('kafka_bridge.client_connect'),
    Params =
        #{action => client_connect,
          node => node(),
          clientid => ClientId,
          username => maybe(Username),
          ipaddress => iolist_to_binary(ntoa(Peerhost)),
          keepalive => maps:get(keepalive, ConnInfo),
          proto_ver => maps:get(proto_ver, ConnInfo)},
    kafka_pub('client.connect', Params).

%%--------------------------------------------------------------------
%% Client connack
%%--------------------------------------------------------------------

on_client_connack(ConnInfo =
                      #{clientid := ClientId,
                        username := Username,
                        peername := {Peerhost, _}},
                  Rc,
                  _AckProp,
                  _Env) ->
    emqx_metrics:inc('kafka_bridge.client_connack'),
    Params =
        #{action => client_connack,
          node => node(),
          clientid => ClientId,
          username => maybe(Username),
          ipaddress => iolist_to_binary(ntoa(Peerhost)),
          keepalive => maps:get(keepalive, ConnInfo),
          proto_ver => maps:get(proto_ver, ConnInfo),
          conn_ack => Rc},
    kafka_pub('client.connack', Params).

%%--------------------------------------------------------------------
%% Client connected
%%--------------------------------------------------------------------

on_client_connected(#{clientid := ClientId,
                      username := Username,
                      peerhost := Peerhost},
                    ConnInfo,
                    _Env) ->
    emqx_metrics:inc('kafka_bridge.client_connected'),
    Params =
        #{action => client_connected,
          node => node(),
          clientid => ClientId,
          username => maybe(Username),
          ipaddress => iolist_to_binary(ntoa(Peerhost)),
          keepalive => maps:get(keepalive, ConnInfo),
          proto_ver => maps:get(proto_ver, ConnInfo),
          connected_at => maps:get(connected_at, ConnInfo)},
    kafka_pub('client.connected', Params).

%%--------------------------------------------------------------------
%% Client disconnected
%%--------------------------------------------------------------------

on_client_disconnected(ClientInfo, {shutdown, Reason}, ConnInfo, Env)
    when is_atom(Reason) ->
    on_client_disconnected(ClientInfo, Reason, ConnInfo, Env);
on_client_disconnected(#{clientid := ClientId, username := Username},
                       Reason,
                       ConnInfo,
                       _Env) ->
    emqx_metrics:inc('kafka_bridge.client_disconnected'),
    Params =
        #{action => client_disconnected,
          node => node(),
          clientid => ClientId,
          username => maybe(Username),
          reason => stringfy(maybe(Reason)),
          disconnected_at => maps:get(disconnected_at, ConnInfo, erlang:system_time(millisecond))},
    kafka_pub('client.disconnected', Params).

%%--------------------------------------------------------------------
%% Client subscribe
%%--------------------------------------------------------------------

on_client_subscribe(#{clientid := ClientId, username := Username},
                    _Properties,
                    TopicTable,
                    {Filter}) ->
    lists:foreach(fun({Topic, Opts}) ->
                     with_filter(fun() ->
                                    emqx_metrics:inc('kafka_bridge.client_subscribe'),
                                    Params =
                                        #{action => client_subscribe,
                                          node => node(),
                                          clientid => ClientId,
                                          username => maybe(Username),
                                          topic => Topic,
                                          opts => Opts},
                                    kafka_pub('client.subscribe', Params)
                                 end,
                                 Topic,
                                 Filter)
                  end,
                  TopicTable).

%%--------------------------------------------------------------------
%% Client unsubscribe
%%--------------------------------------------------------------------

on_client_unsubscribe(#{clientid := ClientId, username := Username},
                      _Properties,
                      TopicTable,
                      {Filter}) ->
    lists:foreach(fun({Topic, Opts}) ->
                     with_filter(fun() ->
                                    emqx_metrics:inc('kafka_bridge.client_unsubscribe'),
                                    Params =
                                        #{action => client_unsubscribe,
                                          node => node(),
                                          clientid => ClientId,
                                          username => maybe(Username),
                                          topic => Topic,
                                          opts => Opts},
                                    kafka_pub('client.unsubscribe', Params)
                                 end,
                                 Topic,
                                 Filter)
                  end,
                  TopicTable).

%%--------------------------------------------------------------------
%% Session subscribed
%%--------------------------------------------------------------------

on_session_subscribed(#{clientid := ClientId, username := Username},
                      Topic,
                      Opts,
                      {Filter}) ->
    with_filter(fun() ->
                   emqx_metrics:inc('kafka_bridge.session_subscribed'),
                   Params =
                       #{action => session_subscribed,
                         node => node(),
                         clientid => ClientId,
                         username => maybe(Username),
                         topic => Topic,
                         opts => Opts},
                   kafka_pub('session.subscribed', Params)
                end,
                Topic,
                Filter).

%%--------------------------------------------------------------------
%% Session unsubscribed
%%--------------------------------------------------------------------

on_session_unsubscribed(#{clientid := ClientId, username := Username},
                        Topic,
                        _Opts,
                        {Filter}) ->
    with_filter(fun() ->
                   emqx_metrics:inc('kafka_bridge.session_unsubscribed'),
                   Params =
                       #{action => session_unsubscribed,
                         node => node(),
                         clientid => ClientId,
                         username => maybe(Username),
                         topic => Topic},
                   kafka_pub('session.unsubscribed', Params)
                end,
                Topic,
                Filter).

%%--------------------------------------------------------------------
%% Session terminated
%%--------------------------------------------------------------------

on_session_terminated(Info, {shutdown, Reason}, SessInfo, Env) when is_atom(Reason) ->
    on_session_terminated(Info, Reason, SessInfo, Env);
on_session_terminated(#{clientid := ClientId, username := Username},
                      Reason,
                      _SessInfo,
                      _Env) ->
    emqx_metrics:inc('kafka_bridge.session_terminated'),
    Params =
        #{action => session_terminated,
          node => node(),
          clientid => ClientId,
          username => maybe(Username),
          reason => stringfy(maybe(Reason))},
    kafka_pub('session.terminated', Params).

%%--------------------------------------------------------------------
%% Message publish
%%--------------------------------------------------------------------

on_message_publish(Message = #message{topic = <<"$SYS/", _/binary>>}, _Env) ->
    {ok, Message};
on_message_publish(Message = #message{topic = Topic, flags = #{retain := Retain}}, Env) ->
    #{filter := Filter} = Env,
    with_filter(fun() ->
                   emqx_metrics:inc('kafka_bridge.message_publish'),
                   {FromClientId, FromUsername} = parse_from(Message),
                   Params =
                       #{action => message_publish,
                         node => node(),
                         from_client_id => FromClientId,
                         from_username => FromUsername,
                         topic => Message#message.topic,
                         qos => Message#message.qos,
                         retain => emqx_message:get_flag(retain, Message),
                         payload => encode_payload(Message#message.payload),
                         ts => Message#message.timestamp},
                   kafka_pub('message.publish', Params),
                   {ok, Message}
                end,
                Message,
                Topic,
                Filter).

%%--------------------------------------------------------------------
%% Message deliver
%%--------------------------------------------------------------------

on_message_delivered(_ClientInfo, #message{topic = <<"$SYS/", _/binary>>}, _Env) ->
    ok;
on_message_delivered(#{clientid := ClientId, username := Username},
                     Message = #message{topic = Topic},
                     {Filter}) ->
    with_filter(fun() ->
                   emqx_metrics:inc('kafka_bridge.message_delivered'),
                   {FromClientId, FromUsername} = parse_from(Message),
                   Params =
                       #{action => message_delivered,
                         node => node(),
                         clientid => ClientId,
                         username => maybe(Username),
                         from_client_id => FromClientId,
                         from_username => FromUsername,
                         topic => Message#message.topic,
                         qos => Message#message.qos,
                         retain => emqx_message:get_flag(retain, Message),
                         payload => encode_payload(Message#message.payload),
                         ts => Message#message.timestamp},
                   kafka_pub('message.delivered', Params)
                end,
                Topic,
                Filter).

%%--------------------------------------------------------------------
%% Message acked
%%--------------------------------------------------------------------

on_message_acked(_ClientInfo, #message{topic = <<"$SYS/", _/binary>>}, _Env) ->
    ok;
on_message_acked(#{clientid := ClientId, username := Username},
                 Message = #message{topic = Topic},
                 {Filter}) ->
    with_filter(fun() ->
                   emqx_metrics:inc('kafka_bridge.message_acked'),
                   {FromClientId, FromUsername} = parse_from(Message),
                   Params =
                       #{action => message_acked,
                         node => node(),
                         clientid => ClientId,
                         username => maybe(Username),
                         from_client_id => FromClientId,
                         from_username => FromUsername,
                         topic => Message#message.topic,
                         qos => Message#message.qos,
                         retain => emqx_message:get_flag(retain, Message),
                         payload => encode_payload(Message#message.payload),
                         ts => Message#message.timestamp},
                   kafka_pub('message.acked', Params)
                end,
                Topic,
                Filter).

%%--------------------------------------------------------------------
%% Internal functions
%%--------------------------------------------------------------------

kafka_pub(Hook, Params) ->
    case ets:lookup(topic_table, Hook) of
        [{_, Topic}] ->
            Partition = application:get_env(?APP, partition, 0),
            Body = emqx_json:encode(Params),
            io:format("publishing to ~p~n", [Topic]),
            ok = brod:produce_sync(brod_client_1, Topic, Partition, <<>>, Body);
        [] ->
            io:format("hook not matched: ~p, all_table: ~p~n", [Hook, ets:tab2list(topic_table)])
    end.

%% add hooks
load_(Hook, Filter) ->
    case Hook of
        'client.connect' ->
            emqx:hook(Hook, {?MODULE, on_client_connect, [{Filter}]});
        'client.connack' ->
            emqx:hook(Hook, {?MODULE, on_client_connack, [{Filter}]});
        'client.connected' ->
            emqx:hook(Hook, {?MODULE, on_client_connected, [{Filter}]});
        'client.disconnected' ->
            emqx:hook(Hook, {?MODULE, on_client_disconnected, [{Filter}]});
        'client.subscribe' ->
            emqx:hook(Hook, {?MODULE, on_client_subscribe, [{Filter}]});
        'client.unsubscribe' ->
            emqx:hook(Hook, {?MODULE, on_client_unsubscribe, [{Filter}]});
        'session.subscribed' ->
            emqx:hook(Hook, {?MODULE, on_session_subscribed, [{Filter}]});
        'session.unsubscribed' ->
            emqx:hook(Hook, {?MODULE, on_session_unsubscribed, [{Filter}]});
        'session.terminated' ->
            emqx:hook(Hook, {?MODULE, on_session_terminated, [{Filter}]});
        'message.publish' ->
            emqx:hook(Hook, {?MODULE, on_message_publish, [{Filter}]});
        'message.acked' ->
            emqx:hook(Hook, {?MODULE, on_message_acked, [{Filter}]});
        'message.delivered' ->
            emqx:hook(Hook, {?MODULE, on_message_delivered, [{Filter}]})
    end.

unload_(Hook) ->
    case Hook of
        'client.connect' ->
            emqx:unhook(Hook, {?MODULE, on_client_connect});
        'client.connack' ->
            emqx:unhook(Hook, {?MODULE, on_client_connack});
        'client.connected' ->
            emqx:unhook(Hook, {?MODULE, on_client_connected});
        'client.disconnected' ->
            emqx:unhook(Hook, {?MODULE, on_client_disconnected});
        'client.subscribe' ->
            emqx:unhook(Hook, {?MODULE, on_client_subscribe});
        'client.unsubscribe' ->
            emqx:unhook(Hook, {?MODULE, on_client_unsubscribe});
        'session.subscribed' ->
            emqx:unhook(Hook, {?MODULE, on_session_subscribed});
        'session.unsubscribed' ->
            emqx:unhook(Hook, {?MODULE, on_session_unsubscribed});
        'session.terminated' ->
            emqx:unhook(Hook, {?MODULE, on_session_terminated});
        'message.publish' ->
            emqx:unhook(Hook, {?MODULE, on_message_publish});
        'message.acked' ->
            emqx:unhook(Hook, {?MODULE, on_message_acked});
        'message.delivered' ->
            emqx:unhook(Hook, {?MODULE, on_message_delivered})
    end.

parse_rule(Rules) ->
    parse_rule(Rules, []).

parse_rule([], Acc) ->
    lists:reverse(Acc);
parse_rule([{Rule, Conf} | Rules], Acc) ->
    Params = emqx_json:decode(iolist_to_binary(Conf)),
    Filter = proplists:get_value(<<"topic">>, Params),
    parse_rule(Rules, [{list_to_atom(Rule), Filter} | Acc]).

with_filter(Fun, _, undefined) ->
    Fun(),
    ok;
with_filter(Fun, Topic, Filter) ->
    case emqx_topic:match(Topic, Filter) of
        true ->
            Fun(),
            ok;
        false ->
            ok
    end.

with_filter(Fun, _, _, undefined) ->
    Fun();
with_filter(Fun, Msg, Topic, Filter) ->
    case emqx_topic:match(Topic, Filter) of
        true ->
            Fun();
        false ->
            {ok, Msg}
    end.

parse_from(Message) ->
    {emqx_message:from(Message), maybe(emqx_message:get_header(username, Message))}.

encode_payload(Payload) ->
    encode_payload(Payload, application:get_env(?APP, payload_encoding, plain)).

encode_payload(Payload, base62) ->
    emqx_base62:encode(Payload);
encode_payload(Payload, base64) ->
    base64:encode(Payload);
encode_payload(Payload, plain) ->
    Payload.

stringfy(Term) when is_binary(Term) ->
    Term;
stringfy(Term) when is_atom(Term) ->
    atom_to_binary(Term, utf8);
stringfy(Term) ->
    unicode:characters_to_binary(
        io_lib:format("~0p", [Term])).

maybe(undefined) ->
    null;
maybe(Str) ->
    Str.
