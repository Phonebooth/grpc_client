%% @doc The interface for grpc_client.
%%
-module(grpc_client).

-export([compile/1, compile/2,
         connect/3, connect/4,
         new_stream/4, new_stream/5,
         send/2, send_last/2,
         unary/6,
         rcv/1, rcv/2,
         get/1,
         ping/2,
         stop_stream/1, stop_stream/2,
         stop_connection/1]).

-type connection_option() ::
    {verify_server_identity, boolean()} |
    {server_host_override, string()} |
    {transport_options, [ssl:ssl_option()] | [gen_tcp:option()]} |
    {http2_client, module()} |
    {http2_options, [term()]}.

-type connection() :: grpc_client_connection:connection().

-type metadata_key() :: binary().
-type metadata_value() :: binary().
-type metadata() :: #{metadata_key() => metadata_value()}.
-type compression_method() :: none | gzip.

-type stream_option() ::
    {metadata, metadata()} |
    {compression, compression_method()} |
    {http2_options, [term()]}.

-type client_stream() :: pid().

-type rcv_response() :: {data, map()} | 
                        {headers, metadata()} |
                        eof | {error, term()}.

-type get_response()  :: rcv_response() | empty.

-type unary_response(Type) :: 
    {ok, #{result := Type,
           status_message := binary(),
           http_status := 200,
           grpc_status := 0,
           headers := metadata(),
           trailers := metadata()}} |
    {error, #{error_type := client | timeout | 
              http | grpc,
              http_status => integer(),
              grpc_status => integer(),
              status_message => binary(),
              headers => metadata(),
              result => Type,
              trailers => grpc:metadata()}}.

-export_type([connection/0,
              stream_option/0,
              connection_option/0,
              client_stream/0,
              unary_response/1,
              metadata/0,
              compression_method/0
             ]).

-spec compile(FileName::string()) -> ok.
%% @equiv compile(FileName, [])
compile(FileName) ->
    grpc_client:compile(FileName, []).

-spec compile(FileName::string(), Options::gbp_compile:opts()) -> ok.
%% @doc Compile a .proto file to generate client stubs and a module
%% to encode and decode the protobuf messages.
%%
%% Refer to gbp for the options. grpc will always use the options
%% 'maps' (so that the protobuf messages are translated to and 
%% from maps) and the option '{i, "."}' (so that .proto files in the 
%% current working directory will be found).
compile(FileName, Options) ->
    grpc_lib_compile:file(FileName, [{generate, client} | Options]).

-spec connect(Transport::tcp|ssl,
              Host::string(),
              Port::integer()) -> {ok, connection()} | {error, term()}.
%% @equiv connect(Transport, Host, Port, [])
connect(Transport, Host, Port) ->
    connect(Transport, Host, Port, []).

-spec connect(Transport::tcp|ssl,
              Host::string(),
              Port::integer(),
              Options::[connection_option()]) -> {ok, connection()}.
%% @doc Start a connection to a gRPC server.
%%
%% If 'verify_server_identity' is true (and Transport == ssl), the client will
%% check that the subject of the certificate received from the server is
%% identical to Host.
%%
%% If it is known that the server returns a certificate with another subject
%% than the host name, the 'server_host_override' option can be used to 
%% specify that other subject.
%%
%% The transport options will be passed to the selected Transport when
%% establishing the connection.
%%
%% The option {'http2_client', module()} enables the selection of
%% an http2 client. The default is http2_client, as an alternative it 
%% is possible to select 'grpc_client_chatterbox_adapter', which 
%% implements an adapter for the chatterbox http/2 client. 
connect(Transport, Host, Port, Options) ->
    grpc_client_connection:new(Transport, Host, Port, Options).

-spec new_stream(Connection::connection(), 
                 Service::atom(), 
                 Rpc::atom(), 
                 DecoderModule::module()) -> {ok, client_stream()}.
%% @equiv new_stream(Connection, Service, Rpc, DecoderModule, []) 
new_stream(Connection, Service, Rpc, DecoderModule) ->
    new_stream(Connection, Service, Rpc, DecoderModule, []).

-spec new_stream(Connection::connection(), 
                 Service::atom(), 
                 Rpc::atom(), 
                 DecoderModule::module(),
                 Options::[stream_option()]) -> {ok, client_stream()}.
%% @doc Create a new stream to start a new RPC.
new_stream(Connection, Service, Rpc, DecoderModule, Options) ->
    grpc_client_stream:new(Connection, Service, Rpc, DecoderModule, Options).

-spec send(Stream::client_stream(), Msg::map()) -> ok.
%% @doc Send a message from the client to the server.
send(Stream, Msg) when is_pid(Stream),
                       is_map(Msg) ->
    grpc_client_stream:send(Stream, Msg).

-spec send_last(Stream::client_stream(), Msg::map()) -> ok.
%% @doc Send a message to server and mark it as the last message 
%% on the stream. For simple RPC and client-streaming RPCs that 
%% should trigger the response from the server.
send_last(Stream, Msg) when is_pid(Stream),
                            is_map(Msg) ->
    grpc_client_stream:send_last(Stream, Msg).

-spec rcv(Stream::client_stream()) -> rcv_response().
%% @equiv rcv(Stream, infinity)
rcv(Stream) ->
    grpc_client_stream:rcv(Stream).
   
-spec rcv(Stream::client_stream(), Timeout::timeout()) -> rcv_response().
%% @doc Receive a message from the server. This is a blocking 
%% call, it returns when a message has been received or after Timeout.
%% Timeout is in milliseconds.
%%
%% Returns 'eof' after the last message from the server has been read.
rcv(Stream, Timeout) ->
    grpc_client_stream:rcv(Stream, Timeout).
     
-spec get(Stream::client_stream()) -> get_response().
%% @doc Get a message from the stream, if there is one in the queue. If not return 
%% 'empty'. This is a non-blocking call.
%%
%% Returns 'eof' after the last message from the server has been read.
get(Stream) ->
    grpc_client_stream:get(Stream).

-spec ping(Connection::connection(),
           Timeout::timeout()) -> {ok, RoundTripTime::integer()} |
                                  {error, term()}.
%% @doc Send a PING request.
ping(Connection, Timeout) ->
    grpc_client_connection:ping(Connection, Timeout).

-spec stop_stream(Stream::client_stream()) -> ok.
%% @equiv stop_stream(Stream, 0)
%%
%% Stops a stream with "NO_ERROR" code.
stop_stream(Stream) ->
    stop_stream(Stream, 0).

-spec stop_stream(Stream::client_stream(), ErrorCode::integer()) -> ok.
%% @equiv stop_stream(Stream, 0)
%%
%% Stops a stream. Depending on the state of the connection a 'RST_STREAM' 
%% frame may be sent to the server with the provided Errorcode (it should be
%% a HTTP/2 error code, see RFC7540).
stop_stream(Stream, ErrorCode) ->
    grpc_client_stream:stop(Stream, ErrorCode).

-spec stop_connection(Connection::connection()) -> ok.
%% @doc Stop a connection and clean up.
stop_connection(Connection) ->
    grpc_client_connection:stop(Connection).

-spec unary(Connection::connection(),
            Message::map(), Service::atom(), Rpc::atom(),
            Decoder::module(),
            Options::[stream_option() |
                      {timeout, timeout()}]) -> unary_response(map()).
%% @doc Call a unary rpc in one go.
%%
%% Set up a stream, receive headers, message and trailers, stop
%% the stream and assemble a response. This is a blocking function.
unary(Connection, Message, Service, Rpc, Decoder, Options) ->
    {Timeout, StreamOptions} = grpc_lib:keytake(timeout, Options, infinity),
    try
        {ok, Stream} = new_stream(Connection, Service,
                                  Rpc, Decoder, StreamOptions),
        Response = grpc_client_stream:call_rpc(Stream, Message, Timeout),
        stop_stream(Stream),
        Response
    catch
        _Type:_Error ->
            {error, #{error_type => client,
                      status_message => <<"error creating stream">>}}
    end.
