#import "Basic";
#import "Compiler";
#import "String";

#run {
    set_working_directory(#filepath);
    build_options := get_build_options();
    build_options.output_type = Build_Output_Type.NO_OUTPUT;
    array_add(*build_options.modules_search_path_array, "lib/");
    set_build_options(build_options);

    debug := true;

    args := compiler_get_command_line_arguments();

    for arg, index : args {
        print("    [%] '%'\n", index, arg);

        if arg == {
            case "debug";
              // ...

            case "release";
              debug = false;

            case;
              print("Error: Unsupported argument: '%'\n", arg);
              exit(1);
        }
    }

    mode : string;

    if debug {
        mode = "DEBUG :: true;";
    } else {
        mode = "DEBUG :: false;";
    }

    // Workspace to compile server
    w := compiler_create_workspace();

    if !w {
        print("[build.jai] 'compiler_create_workspace' failed\n");
        exit(1);
    }

    build_options.output_type = Build_Output_Type.EXECUTABLE;
    build_options.output_executable_name = "cavy";
    build_options.output_path = "";
    set_build_options(build_options, w);

    compiler_begin_intercept(w);

    add_build_file("src/main.jai", w);
    add_build_string(mode, w);
    // ---

    // Compile! Detect Jai's compilation messages during the process.
    while true {
        message := compiler_wait_for_message();

        if !message {
            continue;
        }

        if message.kind == Compiler_Message.Kind.COMPLETE {
            break; // Done compiling.
        }
    }

    compiler_end_intercept(w);
};
