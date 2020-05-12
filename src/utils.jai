

get_iso_date :: () -> string {
    // Is:          Sun May  3 22:30:14 2020
    // Should be:   Sun, 03 May 2020 21:50:17 GMT
    days :: {:string: "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"};
    month :: {:string: "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"};
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

#scope_file
#import "Basic";
#import "Datetime";
