#import "Basic";
#import "POSIX";
#import "String";
#import "Socket";
#import "Random";

/* Goals:
   [x] Handle basic HTTP/1.0 requests
   [ ] Handle SSL
   [ ] Multiple concurrent connections
   [ ] Improve socket library
 */
#load "config.jai";
#load "http.jai";
#load "utils.jai";
#load "threadpool.jai";

SERVER_NAME     :: "Cavy";
SERVER_VERSION  :: "0.0.1";
SERVER_STRING   :: #run sprint("% v%", SERVER_NAME, SERVER_VERSION);
BUFFER_MAX :: 65536;
debug := false;

connection_handle :: (server: *ServerConfig, socket: s32, address: sockaddr_in) {
    client : *HTTPClientConnection = alloc(size_of(HTTPClientConnection));

    array_add(*server.clients, client);

    client.request.headers = New(Table(string, string));
    client.response.headers = New(Table(string, string));
    init(client.request.headers);
    init(client.response.headers);

    request : *u8 = alloc(BUFFER_MAX);
    client.server = server;
    client.socket, client.address = socket, address;
    if client.socket < 0 error("accept");

    notice("Client connected from %", to_string(client.address));

    n := read(client.socket, request, BUFFER_MAX);
    if n < 0 error("reading from socket");

    client.requestbody = to_string(request);
    client.reqid = tprint("%-%-%", random_get(), random_get(), random_get());
    threadpool_task_add(*config.threadpool, client);
}

threadpool_task_process :: (client: *HTTPClientConnection) {
    http_handle_request(client);

    close(client.socket);
    array_unordered_remove_by_value(*client.server.clients, client);
    table_reset(client.request.headers);
    table_reset(client.response.headers);
    free(client.requestbody);
    free(client);
}

server_thread_start :: (thread: *Thread) -> s64 {
    server: *ServerConfig = cast(*ServerConfig) thread.data;

    // Set up temporary storage for this thread:
    ts: Temporary_Storage;
    context.temporary_storage = *ts;

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

    optval : u32 = 1;
    if setsockopt(server_socket, SOL_SOCKET, SO_REUSEADDR, *optval, 4) < 0 {
        warning("Setsockopt failed: %", get_error());
    }

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
init_signal_handlers :: () {
    handle_sigint :: (sig: s32, info: *siginfo_t, secret: *void) #c_call {
        sigint_context: Context;
        push_context sigint_context {
            ts: Temporary_Storage;
            sigint_context.temporary_storage = *ts;
            warning("SIGINT Intercepted! Shutting everything down.");
            shutdown();
        }
    }

    handle_sigpipe :: (sig: s32, info: *siginfo_t, secret: *void) #c_call {
        // We don't care; we're going to handle it elsewhere.
    }

    regular_sigint : sigaction_t;
    regular_sigpipe : sigaction_t;
    sigint : sigaction_t;
    sigpipe : sigaction_t;

    sigint.sa_sigaction = handle_sigint;
    sigpipe.sa_sigaction = handle_sigpipe;
    sigemptyset(*sigint.sa_mask);
    sigemptyset(*sigpipe.sa_mask);
    sigaction(SIGINT, *sigint, *regular_sigint);
    sigaction(SIGINT, *sigpipe, *regular_sigpipe);
}

init_threadpool :: () {
    using config.threadpool;
    num_threads = config.worker_threads;
    threadpool_start(*config.threadpool);
    notice("Started threadpool with % threads.", num_threads);
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

    random_seed(getpid());
    read_config();
    init_signal_handlers();
    init_status_codes();
    init_threadpool();

    for server: config.servers {
        server.shutdown = false;
        thread_init(*server.thread, server_thread_start);
        server.thread.data = server;
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
