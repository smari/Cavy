
autoindex_generate :: (request: *HTTPRequest, dir: string) -> string {
    output := "<html>\n<head>\n%1\n</head>\n<body>\n  %2\n</body>\n</html>";
    header := tprint("<title>Index of %</title>", request.url);

    file_list: String_Builder;

    visitor :: (info: *File_Visit_Info, user_data: *String_Builder) {
        file_html : string;
        if info.is_directory {
            file_html = tprint("    <tr><td><img src=\"/icons/directory.png\"/><a href=\"%1/\">%1/</a></td></tr>\n", info.short_name);
        } else {
            file_html = tprint("    <tr><td><img src=\"/icons/file.png\"/><a href=\"%1\">%1</a></td></tr>\n", info.short_name);
        }
        append(user_data, file_html);
    }

    visit_files(dir, false, *file_list, visitor, visit_directories=true);

    body   := tprint("<h1>Index of %</h1>\n<table><thead><tr><th>Filename</th></tr></thead><tbody>\n%\n</tbody></table>", request.url, builder_to_string(*file_list));
    output  = sprint(output, header, body);
    return output;
}

#scope_file
#import "File_Utilities";
