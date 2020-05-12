// Config file format
ServerConfig :: struct {
    server_socket:   s32;
    listen_host:     string = "0.0.0.0";
    listen_port:     u16 = 80;
    default_charset: string = "utf-8";
    server_name:     string;
    root:            string;
    autoindex:       bool = true;
    index_filenames: [..]string;
    add_headers:     [..]HTTPHeader;

    shutdown:        bool = false;
};

to_string :: (server: *ServerConfig) -> string {
    return tprint("%", <<server);
}

server_config : [..]*ServerConfig;

read_config :: () {
    parse_config_file("default.config");
}

#scope_file

#import "File";
#import "Any";
#import "Unicode";

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
        if s[0] == #char "{" {
            advance(*s);
            return "{", s, true;
        }
        if s[0] == #char "}" {
            advance(*s);
            return "}", s, true;
        }
        if s[0] == #char ";" {
            advance(*s);
            return ";", s, true;
        }
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

eat_token :: (input: *string, eat: string) {
    tok, found := get_next_token(input);
    if tok != eat error(tprint("Config: Expecting '%', got '%'\n", eat, tok));
}

parse_statement :: (input: *string, using cur_server: *ServerConfig) {
    tok, found := get_next_token(input);
    temp : string;
    set : []Any;
    if tok == {
        case "listen";
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
        case "server_name";
            server_name = get_next_token(input);
        case "root";
            root = trim_right(get_next_token(input), "/");
        case "index";
            while true {
                tok, temp, found = peek_next_token(input);
                if tok == ";" { break; }
                array_add(*index_filenames, get_next_token(input));
            }
        case "add_header";
            header: HTTPHeader;
            header.key = get_next_token(input);
            header.value = get_next_token(input);
            array_add(*add_headers, header);
            while true {
                tok, temp, found = peek_next_token(input);
                if tok == ";" { break; }
                if tok == "always" {
                    header.always = true;
                }
            }
    }
    eat_token(input, ";");
}

parse_config_server :: (input: *string) {
    eat_token(input, "{");
    cur_server: *ServerConfig;
    cur_server = New(ServerConfig);
    array_add(*server_config, cur_server);
    while true {
        tok, found := peek_next_token(input);
        if tok == "}" {
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

    while true {
        tok, found := get_next_token(*file_data);
        if found && tok == "server" {
            parse_config_server(*file_data);
        }
        else break;
    }
}

ConfigFile :: struct {
    file_path:      string;  // File location
    orig_file_data: string;  // The full contents of the loaded file.
    file_data:      string;  // Unparsed remainder.
    line:           int = 0;
    col:            int = 0;
}

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
