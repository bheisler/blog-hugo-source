+++
description = ""
draft = true
categories = [""]
tags = ["", ""]
+++

# Intro

# Basic JSON API
- Set up stdio json API, pretty simple. Probably doesn't deserve too much detail.
- I wrote some simple code to read a JSON-encoded command from stdin, call
  a function and write the results back to stdout.
- I'm going to gloss over this part; you can probably guess pretty much what
  the code looks like and I didn't run into any interesting problems or
  new-to-me libraries while writing it.
- Actually, no, that's not correct. I ran into a problem trying to read multiple
  values from the stream. It took me a while to discover the StreamDeserializer
  type
- Looks like, to avoid deadlocks where each process is waiting for the other,
  you need to write a newline and flush the stream after each message.
  Also, for some reason, the JSON API's expect the end of the stream to follow
  the end of the first object, so you have to use StreamDeserializer 
  (serde_json) or JsonReader (GSON) to read multiple values from one stream.

# Error Handling
- Currently my initial attempt just panics if the processing or JSON encoding/
  decoding fails. That's probably not what we want.
- I decided to use the failure crate, which I haven't used before.
- In my case, since errors should be rare, I don't care too much about the
  cost of the error-handling case so I just used the Error type and accepted
  the overhead of allocating if anything fails. This makes it basically trivial
  to handle errors - just return Result<T, Error> and it all just works. Very 
  impressed with the failure crate.

# Database

- Install diesel_cli and setup the project
- `diesel migration generate <name>`
- Write migration script
```
CREATE TABLE feed_entry (
    url TEXT NOT NULL PRIMARY KEY,
    title TEXT NOT NULL,
    time TEXT NOT NULL,
    read INTEGER NOT NULL
)
```
- Generate schema
