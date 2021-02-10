// Smári's standalone Jai utilities, r2
// Hypothetically most of this belongs in the standard library
//  or at least some easily available module.

// Error/warning/notice printing
// TODO: Add syslog support.
notice :: (msg: string, args: ..Any) {
    if debug {
        msgst := tprint(msg, ..args);
        print("[Notice ] %\n", msgst);
    }
}

warning :: (msg: string, args: ..Any) {
    msgst := tprint(msg, ..args);
    print("[Warning] %\n", msgst);
}

error :: (msg: string, args: ..Any, errno:s32=1) {
    errst := tprint(msg, ..args);
    print("[Error  ] %\n", errst);
    exit(errno);
}


// errno() stringification utility function.
get_error :: () -> string {
    err := errno();
    if err == {
        case EPERM; return "Operation not permitted";
        case ENOENT; return "No such file or directory";
        case ENOMEM; return "Out of memory";
        case; return tprint("%", err);
    }
}


// Stat and related file utility functions

stat :: (filename: string) -> stat_t, success:bool {
    status: stat_t;
    if stat(temp_c_string(filename), *status) != 0 {
        return status, false;
    }
    return status, true;
}

is_dir :: (filename: string) -> bool {
    status := stat(filename);
    return S_ISDIR(status.st_mode);
}

is_char_device :: (filename: string) -> bool {
    status := stat(filename);
    return S_ISCHR(status.st_mode);
}

is_block_device :: (filename: string) -> bool {
    status := stat(filename);
    return S_ISBLK(status.st_mode);
}

is_file :: (filename: string) -> bool {
    status := stat(filename);
    return S_ISREG(status.st_mode);
}

is_fifo :: (filename: string) -> bool {
    status := stat(filename);
    return S_ISFIFO(status.st_mode);
}

is_link :: (filename: string) -> bool {
    status := stat(filename);
    return S_ISLNK(status.st_mode);
}

is_socket :: (filename: string) -> bool {
    status := stat(filename);
    return S_ISSOCK(status.st_mode);
}


// Date utils

get_iso_date :: () -> string {
    // Is:          Sun May  3 22:30:14 2020
    // Should be:   Sun, 03 May 2020 21:50:17 GMT
    days :: string.["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
    month :: string.["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
    rawtime: time_t;
    time(*rawtime);
    info : *tm = localtime(*rawtime);
    return tprint("%, % % % %:%:% %",
            days[info.tm_wday],
            formatInt(info.tm_mday, minimum_digits=2),
            month[info.tm_mon],
            info.tm_year,
            formatInt(info.tm_hour, minimum_digits=2),
            formatInt(info.tm_min, minimum_digits=2),
            formatInt(info.tm_sec, minimum_digits=2),
            "UTC" // TODO: Return something other than UTC.
        );
}

// Thread utils
#if OS == .LINUX {
    pthreads :: #foreign_system_library "libpthread";
    pthread_setname_np :: (thread: pthread_t, name: *u8) -> s32 #foreign pthreads;
    pthread_getname_np :: (thread: pthread_t, name: *u8, len: size_t) -> s32 #foreign pthreads;
}

#scope_file
#import "Basic";
#import "Datetime";
