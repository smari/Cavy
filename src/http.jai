#import "Bucket_Array";
#import "Hash_Table";
#import "File_Utilities";
#load "autoindex.jai";

HTTPClientConnection :: struct {
    reqid          : string;
    server         : *ServerConfig;
    requestbody    : string;
    request        : HTTPRequest;
    response       : HTTPResponse;
    socket         : s32;
    address        : sockaddr_in;
    bytes_received : u64;
    bytes_sent     : u64;
    thread         : Thread;
}

HTTPRequest :: struct {
    version        : string;
    verb           : string;
    url            : string;
    headers        : *Table(string, string);
    header_count   : int;
}

HTTPResponse :: struct {
    version        : string;
    status_code    : int;
    headers        : *Table(string, string);
    header_count   : int;
    message_body   : string;
}

Scheme :: enum {
    HTTP;
    HTTPS;
}

URI :: struct {
    scheme         : Scheme;
    host           : string;
    port           : u16;
    abs_path       : string;
}

HTTPStatusCodes : Table(int, string);

add_status_code :: (status_code: int, reason_phrase: string) {
    table_add(*HTTPStatusCodes, status_code, reason_phrase);
}

get_status_code :: (status_code: int) -> string {
    reason_phrase, success := table_find(HTTPStatusCodes, status_code);
    if !success return "Unknown";
    return reason_phrase;
}

init_status_codes :: () {
    init(*HTTPStatusCodes);
    // 1×× Informational
    add_status_code(100, "Continue");
    add_status_code(101, "Switching Protocols");
    add_status_code(102, "Processing");
    // 2×× Success
    add_status_code(200, "OK");
    add_status_code(201, "Created");
    add_status_code(202, "Accepted");
    add_status_code(203, "Non-authoritative Information");
    add_status_code(204, "No Content");
    add_status_code(205, "Reset Content");
    add_status_code(206, "Partial Content");
    add_status_code(207, "Multi-Status");
    add_status_code(208, "Already Reported");
    add_status_code(226, "IM Used");
    // 3×× Redirection
    add_status_code(300, "Multiple Choices");
    add_status_code(301, "Moved Permanently");
    add_status_code(302, "Found");
    add_status_code(303, "See Other");
    add_status_code(304, "Not Modified");
    add_status_code(305, "Use Proxy");
    add_status_code(307, "Temporary Redirect");
    add_status_code(308, "Permanent Redirect");
    // 4×× Client Error
    add_status_code(400, "Bad Request");
    add_status_code(401, "Unauthorized");
    add_status_code(402, "Payment Required");
    add_status_code(403, "Forbidden");
    add_status_code(404, "Not Found");
    add_status_code(405, "Method Not Allowed");
    add_status_code(406, "Not Acceptable");
    add_status_code(407, "Proxy Authentication Required");
    add_status_code(408, "Request Timeout");
    add_status_code(409, "Conflict");
    add_status_code(410, "Gone");
    add_status_code(411, "Length Required");
    add_status_code(412, "Precondition Failed");
    add_status_code(413, "Payload Too Large");
    add_status_code(414, "Request-URI Too Long");
    add_status_code(415, "Unsupported Media Type");
    add_status_code(416, "Requested Range Not Satisfiable");
    add_status_code(417, "Expectation Failed");
    add_status_code(418, "I'm a teapot");
    add_status_code(421, "Misdirected Request");
    add_status_code(422, "Unprocessable Entity");
    add_status_code(423, "Locked");
    add_status_code(424, "Failed Dependency");
    add_status_code(426, "Upgrade Required");
    add_status_code(428, "Precondition Required");
    add_status_code(429, "Too Many Requests");
    add_status_code(431, "Request Header Fields Too Large");
    add_status_code(444, "Connection Closed Without Response");
    add_status_code(451, "Unavailable For Legal Reasons");
    add_status_code(499, "Client Closed Request");
    // 5×× Server Error
    add_status_code(500, "Internal Server Error");
    add_status_code(501, "Not Implemented");
    add_status_code(502, "Bad Gateway");
    add_status_code(503, "Service Unavailable");
    add_status_code(504, "Gateway Timeout");
    add_status_code(505, "HTTP Version Not Supported");
    add_status_code(506, "Variant Also Negotiates");
    add_status_code(507, "Insufficient Storage");
    add_status_code(508, "Loop Detected");
    add_status_code(510, "Not Extended");
    add_status_code(511, "Network Authentication Required");
    add_status_code(599, "Network Connect Timeout Error");
}

HTTP_VERBS :: {:string: "GET", "POST", "PUT", "DELETE", "HEAD", "CONNECT" };

send_http_response :: (client: *HTTPClientConnection, status_code: int) {
    client.response.status_code = status_code;
    send_http_response(client);
}

send_http_response :: (using client: *HTTPClientConnection) {
    // TODO: Rather than send it all as one big string, how about we send bits
    //       as we go? Saves us from having to to_string() the entire thing!
    //          - smari 12020-05-07
    // Update: Now to_string() is get_response_headers() and only returns
    //       headers. As a result, response.message_body is sent separately.
    //          - smari 12020-05-12
    bytes : s64;
    if !response.version response.version = request.version;
    if response.status_code >= 300 {
        // TODO: Here we should check for custom error handlers.
        add_response_header(*response, "Content-Type", tprint("text/html; charset=%", client.server.default_charset));
        response_set_body(*response,
            tprint("<html>\n<head>\n  <title>%1 %2</title>\n</head>\n<body>\n  <h1>%1 %2</h1>\n</body>\n</html>\n",
            response.status_code, get_status_code(response.status_code)));
    }

    add_response_header(*response, "Date", get_iso_date());
    add_response_header(*response, "Content-Length", tprint("%", response.message_body.count));
    add_response_header(*response, "X-Request-Id", client.reqid);

    respstr := get_response_headers(response);
    bytes = write(socket, respstr);
    if bytes == -1 {
        if errno() == {
            case EPIPE; notice("Client disappeared."); return;
        }
    }
    bytes = write(socket, response.message_body);
    if bytes == -1 {
        if errno() == {
            case EPIPE; notice("Client disappeared."); return;
        }
    }
}

add_response_header :: (response: *HTTPResponse, key: string, value: string) {
    table_add(response.headers, key, value);
}

response_set_body :: (using response: *HTTPResponse, body: string) {
    message_body = body;
}

get_response_headers :: (using response: HTTPResponse) -> string {
    str: String_Builder;
    append(*str, tprint("% % %\r\n", version, status_code, get_status_code(status_code)));
    for value,key:headers {
        append(*str, tprint("%: %\r\n", key, value));
    }
    append(*str, "\r\n");
    return builder_to_string(*str);
}

add_request_header :: (request: *HTTPRequest, key: string, value: string) {
    table_add(request.headers, key, value);
}

parse_header :: (header: string) -> key: string, value: string, success: bool #must {
    key : string;
    key.data = header.data;
    key.count = header.count;
    orig := header;
    if header.count == 0 { return "", "", false; }
    while true {
        if header[0] == #char "\r" { return "", "", false; }
        if header[0] == #char ":" {
            key.count -= header.count;
            advance(*header); // Skip ":" and any spaces after:
            while header[0] == #char " " { advance(*header); }
            break;
        }
        advance(*header);
        if header.count == 0 {
            warning("Received malformed header '%'", orig);
            return "", "", false;
        }
    }
    return key = key, value = header, success = true;
}

parse_request_uri :: (uri: string) -> URI, success: bool {
    // https://www.w3.org/Protocols/rfc2616/rfc2616-sec5.html
    resp : URI;
    parts : []string;
    start : int;

    // "*" is a valid Request-URI if the request doesn't apply to
    //  a particular resource.
    if uri == "*" {
        resp.abs_path = uri;
    }
    // Check for abs_path:
    else if starts_with(uri, "/") {
        parts = split(uri, "/");
        resp.abs_path = uri;
        start = 0;
    }
    // Check for Absolute-URI:
    else if starts_with(uri, "http") {
        // Could be HTTP or HTTPS, but at least it's an absolute URI!
        parts = split(uri, "/");
        if parts.count < 4 {
            return resp, false;
        }
        if parts[0] == {
            case "https:"; resp.scheme = Scheme.HTTPS;
            case "http:"; resp.scheme = Scheme.HTTP;
        }
        // TODO: Add support for BasicAuth strings.
        host_port := split(parts[2], ":");
        resp.host = copy_string(host_port[0]);
        if host_port.count == 1 {
            resp.port = 80;
        } else {
            resp.port = parse_int(*host_port[1], u16);
        }
        array_reset(*host_port);
        start = 3;
    }
    // TODO: Unimplemented: Check for authority (for CONNECT method) (see standard)

    abs_path_parts : [..]string;
    for start..parts.count-1 {
        if parts[it] == "" continue;
        // TODO: We're stripping ".." for security, but might want to be smarter about that.
        if parts[it] == ".." continue;
        array_add(*abs_path_parts, parts[it]);
    }
    resp.abs_path = join(..abs_path_parts, separator="/", separator_before_first=true);
    if resp.abs_path == "" resp.abs_path = "/";

    array_reset(*parts);
    return resp, true;
}


resolve_location :: (using client: *HTTPClientConnection) {
    // TODO: Handle URL maps and dispatch to the correct handler.
    // HTTP/1.0 -> /...
    // HTTP/1.1 -> https://foo.bar/...

    uri := parse_request_uri(request.url);

    /*if server.server_name != "_" && server.server_name != uri.host {
        print("Request is to %, but we're on %.\n", uri.host, server.server_name);
    }*/
    local_file := join(server.root, uri.abs_path);
    // Check if it's a directory!
    if is_dir(local_file) {
        // Permanent redirect if the server asked for a dir without a trailing slash.
        if request.url[request.url.count-1] != #char "/" {
            response.status_code = 301;
            new_url := join(request.url, "/");
            add_response_header(*response, "Location", new_url);
            return;
        }

        // First we try indexes
        found := false;
        for index:server.index_filenames {
            idxfile := join(local_file, index);
            if file_exists(idxfile) {
                free(local_file);
                local_file = idxfile;
                found = true;
                break;
            }
        }

        // If no index found, try to autoindex
        if !found && server.autoindex {
            index := autoindex_generate(*request, local_file);
            response_set_body(*response, index);
            add_response_header(*response, "Content-Type", "text/html");
            return;
        }

        // Finally we 404 if still not found.
        if !found {
            response.status_code = 404;
            return;
        }
    }

    // Either resolved to a file or found an index file:
    // TODO: Here we should give generic MIME info.
    if ends_with(local_file, ".html") {
        add_response_header(*response, "Content-Type", "text/html");
    }
    buf, success := read_entire_file(local_file);
    if !success { response.status_code = 404; return; }
    response_set_body(*response, buf);
    free(local_file);
}

http_handle_request :: (using client: *HTTPClientConnection) {
    lines := split(requestbody, "\r\n");
    defer array_reset(*lines);
    if !lines.count return;
    first_line := split(lines[0], " ");
    defer array_reset(*first_line);

    if array_find(HTTP_VERBS, first_line[0]) {
        if first_line.count < 3 {
            // We need at minimum a verb, a URL, and a version.
            return;
        }
        request.verb = copy_string(first_line[0]);
        request.url = copy_string(first_line[1]);
        request.version = copy_string(first_line[2]);

        for line: lines {
            if it_index == 0 continue; // We've already done first line.
            if !line break; // Empty line does indicate that we're done.
            key, value, success := parse_header(line);
            if success {
                add_request_header(*request, key, value);
            } else {
                // TODO: How do we handle failure?
            }
        }
        // TODO: Here we should parse request body!

        response.version = "";
        response.status_code = 200;
        for value,key:client.server.add_headers {
            // Adding headers that should always be added.
            add_response_header(*response, key, value);
        }
        resolve_location(client);
        send_http_response(client);

        reset_temporary_storage();
    } else {
        // We got a nonsense verb, or nothing at all.
        warning("Don't know what '%' means!", first_line[0]);
        return;
    }
}
