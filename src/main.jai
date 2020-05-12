#import "Basic";
#import "POSIX";
#import "String";
#import "Socket";

/* Goals:
   [x] Handle basic HTTP/1.0 requests
   [ ] Handle SSL
   [ ] Multiple concurrent connections
   [ ] Improve socket library
 */
 #load "config.jai";
 #load "http.jai";
 #load "utils.jai";

SERVER_NAME     :: "Cavy";
SERVER_VERSION  :: "0.0.1";
SERVER_STRING   :: #run sprint("% v%", SERVER_NAME, SERVER_VERSION);
debug := false;

connection_handle :: (server: *ServerConfig, socket: s32, address: sockaddr_in) {
    client : *HTTPClientConnection = alloc(size_of(HTTPClientConnection));
    BUF_MAX :: 65536;
    request : [BUF_MAX]u8;
    client.server = server;
    client.socket, client.address = socket, address;
    if client.socket < 0 error("accept");

    notice("Client connected from %", to_string(client.address));

    n := read(client.socket, *request, BUF_MAX);
    if n < 0 error("reading from socket");

    http_handle_request(client, to_string(request));

    close(client.socket);
    table_reset(*client.request.headers);
    table_reset(*client.response.headers);
    free(client);
}

server_thread_start :: (thread: *Thread) -> s64 {
    server: *ServerConfig = cast(*ServerConfig) thread.data;
    notice("Running inside of thread %.", thread.index);
    #if OS_LINUX {
        // Custom thread names for Linux.
        shortname := server.server_name;
        if shortname.count > 15 shortname.count = 15;
        shortname_c := to_c_string(shortname);
        res := pthread_setname_np(thread.thread_handle, shortname_c);
        free(shortname_c);
    }
    server_start(server);
    notice("Thread % terminating.", thread.index);
    return 0;
}

server_start :: (using server: *ServerConfig) {
    server.running = true;
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
    server.running = false;
}

// Signal handling
setup_signal_handlers :: () {
    handle_sigint :: (sig: s32, info: *siginfo_t, secret: *void) #c_call {
        sigint_context: Context;
        push_context sigint_context {
            // Need to set up temporary storage here.
            warning("SIGINT Intercepted! Shutting everything down.");
            shutdown();
        }
    }

    regular_sigint : sigaction_t;
    sigint : sigaction_t;

    sigint.sa_sigaction = handle_sigint;
    sigemptyset(*sigint.sa_mask);
    sigaction(SIGINT, *sigint, *regular_sigint);
}

shutdown :: () {
    for server: config.servers {
        server.shutdown = true;
        close(server.server_socket);
        thread_destroy(*server.thread);
        deinit_server(server);
    }
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
    for server: config.servers {
        server.shutdown = false;
        thread_init(*server.thread, server_thread_start);
        server.thread.data = server;
        // server_start(server);
        notice("Starting thread for server %", server.server_name);
        thread_start(*server.thread);
    }

    done := false;
    while !done {
        count := 0;
        for server: config.servers {
            done = true;
            if server.shutdown continue;
            done = false;
            count += 1;
        }
        sleep_milliseconds(1000);
    }

    shutdown();
}
