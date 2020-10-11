
# Cavy

A toy HTTP daemon written in Jai. It's a bit like a member of the Caviidae family.

I highly recommend against using this web server in reality. Use something like
nginx instead. I wrote this server in order to experiment with Jai and refresh
some skills. It's not intended as more than a plaything.

## Building and running

Depends on my Socket and Datetime libaries being in `lib/`

Run:
```
$ jai build.jai
```

The executable is `cavy`. Enjoy!

## Features

 - [x] Basic HTTP/1.0 and HTTP/1.1 requests
 - [x] Autoindexing
 - [x] Nginx-style config files
 - [ ] HTTPS
 - [x] Multithreading (per server coordinators and a threadpool)

## TODO

 - [ ] Check for memory leaks
 - [ ] Fix SIGINT handler so it actually exits
 - [ ] Support more configuration/generalize config parser
 - [ ] Support location directives
 - [ ] Customizable error pages
 - [ ] Customizable index pages
