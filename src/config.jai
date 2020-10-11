// Config file format
ServerConfig :: struct {
    listen_host     : string = "0.0.0.0";   @compound:listen
    listen_port     : u16 = 80;             @compound:listen
    default_charset : string = "utf-8";
    server_name     : string;
    root            : string;
    autoindex       : bool = true;
    index_filenames : [..]string;           @name:index
    add_headers     : Table(string, string);@name:add_header
    always_headers  : [..]string;           @noconfig // temporarily @noconfig

    // Runtime stuff:
    server_socket   : s32;                  @noconfig
    thread          : Thread;               @noconfig
    clients         : [..]*HTTPClientConnection; @noconfig
    running         : bool = false;         @noconfig
    shutdown        : bool = false;         @noconfig
};

to_string :: (server: *ServerConfig) -> string {
    return tprint("%", <<server);
}

Config :: struct {
    user            : string;
    pid             : u32;               @noconfig
    pidfile         : string;
    servers         : [..]*ServerConfig; @block:server

    worker_threads  : u32 = 10;          @noconfig
    threadpool      : ThreadPool;        @noconfig // (*HTTPClientConnection);
};

HTTPConfig :: struct {
    sendfile        : bool;
    tcp_nopush      : bool;
    access_log      : string;
    error_log       : string;
    gzip            : bool;
}

config : Config;

read_config :: () {
    parse_config_file("default.config");
}

deinit_server :: (server: *ServerConfig) {
    array_reset(*server.index_filenames);
    array_reset(*server.always_headers);
    table_reset(*server.add_headers);
    free(server);
}


#scope_file

#import "File";
#import "Any";
#import "Unicode";
#import "Thread";

accept_token :: (ch: string) #expand {
    if `s[0] == ch[0] {
        advance(*`s);
        return ch, `s, true;
    }
}

peek_next_token :: (st: *string) -> (tok: string, remainder: string, found: bool) {
    // Yes I guess we are making a tokenizer.
    s := <<st;
    while true {
        if s.count == 0 { return "", s, false; }
        if is_space(s[0]) {
            advance(*s);
            continue;
        }
        if s[0] == #char "#" {
            while s[0] != 10 {
                advance(*s);
            }
            advance(*s);
            continue;
        }
        accept_token("{");
        accept_token("}");
        accept_token(";");
        if s[0] == #char "\"" {
            advance(*s);
            ident := s;
            while s[0] != #char "\"" {
                advance(*s);
            }
            ident.count -= s.count;
            advance(*s);
            return ident, s, true;
        }
        if is_print(s[0]) {
            ident := s;
            while is_print(s[0]) && !is_space(s[0]) && s[0] != #char ";" {
                advance(*s);
            }
            ident.count -= s.count;
            return ident, s, true;
        }
    }
    return "", s, false;
}

get_next_token :: (st: *string) -> (tok: string, found: bool) {
    tok, s, found := peek_next_token(st);
    <<st = s;
    return tok, found;
}

eat_token :: inline (input: *string, eat: string) {
    tok, found := get_next_token(input);
    if tok != eat error(tprint("Config: Expecting '%', got '%'\n", eat, tok));
}

parse_statement :: (input: *string, using cur_server: *ServerConfig) {
    tok, found := get_next_token(input);
    temp : string;
    set : []Any;
    if tok == "listen" {
        // Format here is "<port>" or "<ip>:<port>", or "<host>:<port>".
        // IPv6 addresses are "[<ip>]".
        temp = copy_string(get_next_token(input));
        // Try port only first:
        found, set = scan("%i", temp);
        if found {
            listen_port = any_as(set[0], u16);
        } else {
            port, found := find_character_from_left(temp, #char ":");
            if found {
                temp.count -= port.count;
                found, set = scan(":%i", port);
                if found { listen_port = any_as(set[0], u16); return; }
            }
            listen_host = copy_string(temp);
        }
    }
    if tok == "server_name" { server_name = get_next_token(input); }
    if tok == {
        case "root";
            root = trim_right(get_next_token(input), "/");
        case "index";
            while true {
                tok, temp, found = peek_next_token(input);
                if tok == ";" { break; }
                array_add(*index_filenames, get_next_token(input));
            }
        case "add_header";
            key := get_next_token(input);
            value := get_next_token(input);
            table_add(*add_headers, key, value);
            while true {
                tok, temp, found = peek_next_token(input);
                if tok == ";" { break; }
                if tok == "always" {
                    array_add(*always_headers, key);
                }
            }
    }
    eat_token(input, ";");
}

parse_config_server :: (input: *string) {
    eat_token(input, "{");
    cur_server: *ServerConfig;
    cur_server = New(ServerConfig);
    array_add(*config.servers, cur_server);

    table_add(*cur_server.add_headers, "Server", SERVER_STRING);
    while true {
        tok, found := peek_next_token(input);
        if tok == "}" {
            eat_token(input, "}");
            break;
        } else {
            parse_statement(input, cur_server);
        }
    }
}

parse_config_file :: (filename: string) {
    using handler: ConfigFile;

    init(*handler, filename);
    defer deinit(*handler);

    parse_block(*config, *file_data, true);
    /*
    while true {
        tok, found := get_next_token(*file_data);
        if !found break;

        if tok == "server" {
            parse_config_server(*file_data);
        } else if tok == "http" {
            http := New(HTTPConfig);
            block := parse_block(http, *file_data);
            print("Block: %", block);
        } else {
            error("Unexpected token % in config file.", tok);
        }
    }
    */
}

ConfigFile :: struct {
    file_path       : string;  // File location
    orig_file_data  : string;  // The full contents of the loaded file.
    file_data       : string;  // Unparsed remainder.
    line            : int = 0;
    col             : int = 0;
}


// Advanced parsing test {{
#import "Reflection";

has_note :: (m: $T, n: string) -> bool {
    for note:m.notes {
        if note == n return true;
    }
    return false;
}

get_note :: (m: $T, n: string) -> string, found:bool {
    for note:m.notes {
        if begins_with(note, n) {
            while note[0] != #char ":" advance(*note);
            advance(*note);
            return note, true;
        }
    }
    return "", false;
}

any :: (needle: $T, haystack: []$U) -> bool {
    for m:haystack {
        #if U == T {
            if m == needle return true;
        } else {
            if m.name == needle return true;
        }
    }
    return false;
}


inject_token :: (data: $T, member: $U, token: string) {
    BOOL_VALUES_TRUE  :: string.["true", "on", "1"];
    BOOL_VALUES_FALSE :: string.["false", "off", "0"];

    out: Any;
    out.value_pointer = (cast(*u8)data) + member.offset_in_bytes;
    out.type = member.type;
    rhs : string;
    if member.type == type_info(bool) {
        if any(token, BOOL_VALUES_TRUE)         { rhs = "true";
        } else if any(token, BOOL_VALUES_FALSE) { rhs = "false";
        } else error("Unknown boolean value '%'", token);
    } else if member.type == type_info(string) {
        str := copy_string(token);
        (cast(*string)out.value_pointer).data = str.data;
        (cast(*string)out.value_pointer).count = str.count;
        return;
    } else if member.type == type_info(u32) {
        rhs = token;
    } else {
        print("Dunno how to handle type on %.\n", member.name);
    }
    set_value_from_string(out, rhs);
}

get_member_pointer :: (data: $T, member: $U) -> Any {
    out: Any;
    out.value_pointer = (cast(*u8)data) + member.offset_in_bytes;
    out.type = member.type;
    return out;
}

parse_block :: (target: $T, input: *string, bare_block := false, target_info: *Type_Info_Struct = null) {
    info : *Type_Info_Struct;
    if target_info info = target_info;
    else info = xx type_info(type_of(<< target));
    print(">>> Parse block (target: %)\n", <<info);

    if !bare_block {
        for member:info.members {
            if has_note(member, "preblock") {
                tok := get_next_token(input);
                inject_token(target, member, tok);
            }
        }
        eat_token(input, "{");
    }

    while true {
        tok, found := peek_next_token(input);
        if !found break;                // End of stream?
        if !bare_block && tok == "}" {  // Are we at the end of the block?
            break;
        } else {                        // Okay let's check if we have a block..
            key := get_next_token(input);
            member := get_field(info, key);

            if member == null {
                for m:info.members {
                    // TODO: Can we not require block annotations?
                    blockname, found := get_note(m, "block:");
                    if found {
                        // Found a block info.
                        member = *m;
                        blocktype : *Type_Info_Struct;
                        if member.type.type == .ARRAY {
                            type : *Type_Info_Array = xx member.type;
                            if type.element_type.type == .POINTER {
                                pointer_type : *Type_Info_Pointer = xx type.element_type;
                                blocktype = xx pointer_type.pointer_to;
                            }
                        }
                        if !blocktype error("Couldn't find blocktype");
                        pointer := alloc(blocktype.runtime_size);
                        if blocktype.initializer {
                            blocktype.initializer(target);
                        } else {
                            memset(target, 0, blocktype.runtime_size);
                        }
                        parse_block(pointer, input, target_info=blocktype);
                        // No wait we want to add to an array!
                        destination := get_member_pointer(target, member);
                        //array_add(destination, pointer);
                        // inject_pointer(target, member, pointer);
                        break;
                    }
                }

                if member == null {
                    for m:info.members {
                        blockname, found := get_note(m, "compound:");
                        if found && blockname == key {
                            // Found a compound block
                        }
                    }
                }
            } else { // A regular statement.
                if member == null error("Unknown identifier '%' in config file.", tok);
                if has_note(member, "noconfig") error("'%' is not configurable.", tok);
                if has_note(member, "preblock") error("Trying to assign a block designation variable.");

                value := get_next_token(input);
                inject_token(target, member, value);
                eat_token(input, ";");
            }

        }
    }
    if !bare_block eat_token(input, "}");
    print("<<< Parse Block\n");

    print("Data: %\n", <<target);
}

config_blocks : Table(string, Type);
init_blocks :: () {
    table_add(*config_blocks, "CORE", Config);
    table_add(*config_blocks, "server", ServerConfig);
    table_add(*config_blocks, "http", HTTPConfig);
}

// }}

deinit :: (x: *ConfigFile) { free(x.orig_file_data); }
init :: (using x: *ConfigFile, path: string) {
    success: bool;
    file_path = path;
    file_data, success = read_entire_file(file_path);
    orig_file_data = file_data;
    if !success {
        error(tprint("Could not load config file %", path));
    }
}
