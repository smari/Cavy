#import "Basic";
#import "POSIX";
#import "String";
#import "Socket";

/* Goals:
   [ ] Handle basic HTTP/1.0 requests
   [ ] Handle SSL
   [ ] Multiple concurrent connections
   [ ] Improve socket library
 */
 #load "config.jai";
 #load "http.jai";
 #load "utils.jai";

debug := false;

connection_handle :: (server: *ServerConfig, socket: s32, address: sockaddr_in) {
    client : HTTPClientConnection;
    BUF_MAX :: 65536;
    request : [BUF_MAX]u8;
    client.server = server;
    client.socket, client.address = socket, address;
    if client.socket < 0 error("accept");

    notice("Client connected from %", to_string(client.address));

    n := read(client.socket, *request, BUF_MAX);
    if n < 0 error("reading from socket");

    http_handle_request(server, client, to_string(request));

    close(client.socket);
    notice("Client disconnected.");
}

server_start :: (using server: *ServerConfig) {
    server_socket = socket(AF_INET, SOCK_STREAM, 0);
    if server_socket < 0 error("opening socket");

    optval := 1;
    setsockopt(server_socket, SOL_SOCKET, SO_REUSEADDR, *optval, size_of(socklen_t));

    if bind(server_socket, listen_host, listen_port) < 0 {
        err := errno();
        if err == {
            case EACCES; error("Attempting to listen on %:% without superuser privileges.", listen_host, listen_port, err);
            case EADDRINUSE; error("Address in use: %:%.", listen_host, listen_port, err);
            case; error("Unknown error % when binding.", err, err);
        }
    }
    if listen(server_socket, 5) < 0 error("listen");

    defer close(server_socket);

    notice("Listening on %:%", listen_host, listen_port);
    while !server.shutdown {
        socket, address := accept(server_socket);
        if socket < 0 { break; }
        connection_handle(server, socket, address);
    }
}

// Signal handling
setup_signal_handlers :: () {
    handle_sigint :: (sig: s32, info: *siginfo_t, secret: *void) #c_call {
        sigint_context: Context;
        push_context sigint_context {
            notice("SIGINT Intercepted! Shutting everything down.");
            for server: server_config {
                close(server.server_socket);
            }
        }
    }

    regular_sigint : sigaction_t;
    sigint : sigaction_t;

    sigint.sa_sigaction = handle_sigint;
    sigemptyset(*sigint.sa_mask);
    sigaction(SIGINT, *sigint, *regular_sigint);
}


main :: () {
    idx := 1;
    args := get_command_line_arguments();
    defer array_reset(*args);
    while idx < args.count {
        if args[idx] == {
            case "-d"; debug = true; notice("Debugging enabled.");
            case; print("Unknown parameter %", args[idx]);
        }
        idx += 1;
    }

    setup_signal_handlers();
    read_config();
    init_status_codes();
    for server: server_config {
        server_start(server);
    }
}
