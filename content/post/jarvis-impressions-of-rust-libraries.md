+++
date = "2018-04-22T16:00:00-06:00"
title = "JARVIS - Notes on Rust Crates From Writing an RSS Reader"
tags = ["Rust", "JARVIS"]
categories = ["code"]
author = "Brook Heisler"
+++

Way back in the dim mists of history (back in university) I wrote myself a
custom RSS reader in Java and called it JARVIS[^jarvis]. You see, I read a lot of
webcomics. Like, a lot. Some webcomics provide RSS feeds, but some don't, and
as my collection grew it started to become a hassle to use Firefox's live
bookmarks to manage it all. Ultimately, I wrote up a quick Swing GUI to use as
a single interface for keeping up with blogs and tracking which comics had
published updates since the last time I'd checked[^programming]. Over the years, I
periodically make upgrades to it - performing the HTTP requests in parallel,
for example, or adding caching. I recently completed such a round of upgrades,
rewriting large portions of the code from a mixture of Scala and Java into
Rust. This brought me into contact with a number of Rust libraries that I've
never used before. I hope my impressions can be useful to the maintainers of
those libraries and to other Rust programmers.

[^jarvis]: Yes, like Tony Stark's house AI. I had much grander ambitions when I named this project.
[^programming]: As a side note, how cool is it that we as programmers can just go do stuff like that? Somehow that never seems to get old for me.

## Basic Design

At some point over the years I'd rewritten the whole database access layer and
HTTP-fetching code in Scala. Scala is a great language, but I haven't used it
in years and so this code was starting to get very hard to maintain. The plan
was to rewrite all of that into either Rust or Java. Of course, Rust doesn't yet
run on the JVM, so I needed to decide how I was going to integrate the two.

I could have gone with JNI or JNA or some other Java FFI system, but I figured
that would be more complex than I wanted. Also, I eventually plan to convert
this into an HTTP server so that I can access it from any device. Ultimately,
I settled on launching a background process and communicating with it by
serializing JSON messages over stdin/stdout. In retrospect, that was probably a
mistake; if I were doing this again I think I should have just had the backend
process start up a simple HTTP server on localhost and connected to that instead
of messing around with stdin/stdout.

The backend process has three main responsibilities. It stores data and makes
it available for some limited querying by the GUI. It performs HTTP requests
for RSS feeds; either simple fetches for regular news feeds or with some simple
date/time logic attached to guess whether webcomics that don't have RSS feeds
would have updated. Finally, I've come up with the concept of an archive
cursor, which takes a bit of explaining. Fellow webcomics fans will no doubt be
familiar with the [Archive
Binge](http://tvtropes.org/pmwiki/pmwiki.php/Main/ArchiveBinge), where someone
starts at the beginning of the archives and goes on reading until caught up to
the present. This can take hours or even days for very long comics, and I
typically don't have that much unbroken time. As an alternative, I've set up
JARVIS to automatically find the next 3-5 pages per day so I can read them.
This requires scraping the pages to automatically find the "Next Page" links.
I've found this to be a great way to get caught up on new webcomics or to
re-read old favorites while only investing 10-15 minutes a day rather than
seven-hour marathon sessions.

## Basic JSON API

I didn't originally expect this to be difficult. "You just connect serde and
GSON to stdin/out" I thought "That seems pretty simple". Famous last words.
I ran into two major problems doing that. First, both `GSON` and `serde_json`
expected that there would be no more data after the end of the first record,
which wasn't true in this case. Second, I ran into deadlocks aplenty.

The solution to the first problem wasn't actually so hard. After asking around
I discovered that `serde_json` has a [`StreamDeserializer`](https://docs.serde.rs/serde_json/struct.StreamDeserializer.html) iterator which
does precisely what I wanted (`GSON` calls it a [`JSONReader`](https://google.github.io/gson/apidocs/com/google/gson/stream/JsonReader.html)).

The second problem wasn't easily solved by a library. It took me a little while
to iron out all of the deadlocks. The problem is that each side of the
communication will write a message and then wait for the response (or in the
case of the backend, will wait for the next command). If both sides end up
waiting at the same time, you get a deadlock.

Most languages (including Rust) will buffer stdout to avoid the overhead of
calling out to the OS for every character. Exactly when that buffer is flushed
is usually not documented, though. It is typically flushed when the process
writes a newline character, but not necessarily. Also, `serde_json` at least
expects there to be some kind of separation between each message in a stream
such as a newline. Ultimately, what I settled on is to write the message,
write a newline character, and then explicitly flush the output stream.

Once I got all of that working, the rest of the JSON interface was pretty
straightforward, so I won't go into much detail on that.

## Error Handling

With all of this JSON parsing, database access and HTTP fetching going on, 
there's a lot of room for errors to occur. I opted to set up a decent
error-handling system early on, with the new `failure` crate.

My error-handling needs are pretty simple; I just need to bubble errors up to
the JSON API layer where they can be reported back to the GUI process. `failure`
provides a variety of different ways to handle errors to represent different
performance and effort tradeoffs. I picked the `Error` type, which requires
basically no effort at the cost of always allocating when an error is created.
I simply return a `Result<T, Error>` from all of my functions that can fail,
and print the error message at the top level. I was quite impressed by how
easy it was. I'm not concerned about the allocation here; for this code errors
should be rare and performance is not a top concern anyway.

## Database

For database access, I used the `diesel` crate with a Sqlite database file.
Overall, it worked quite well - the resulting code is much clearer than the
code it replaced. It does make me a bit nervous though. The major reason why I
decided to replace the Scala code initially was because I was having a lot of
trouble remembering how to work with the heavily DSL-based `Slick` library, and
I'm concerned that I might have a similar problem with `diesel` in the future.
I think it will be less pronounced, but I still have to remember, for example,
that I need to use `diesel::insert_into(feed)` for inserts but `feed.load` for
queries. On the good side, even the DSL-based Diesel code is easily readable;
I'm just not sure I'll be able to remember how to write it without referencing
the documentation.

Speaking of the documentation, there are a few areas I found where it could be
improved. In particular, the documentation on foreign-key relationships and
JOINs is buried in the API docs where it's kind of hard to find. It would be
nice if there was a guide to doing these things on the website with the other
guides, or at least some links to the right place in the API docs to make it
easier to find. Having said that, I like how Diesel makes foreign-key queries
very explicit, rather than trying to fetch a whole object graph like some ORMs
do.

One comment is that (depending on how you design your database) the DSL imports
can clash with likely variable names. For example, when inserting a new record
into the `feed` table, it's pretty reasonable to do something like this:

```
use ::schema::feed::dsl::*;
let feed = ...
diesel::insert_into(feed).values(feed).execute(...);
```

Except that this causes a name collision between the `feed` table object and the
`feed` structure being inserted, so you have to artificially rename the value.
Over time I might gravitate towards using `schema::feed::table` or something
similar to make it really clear what is being referenced.

Finally, I had some trouble accessing the database in multiple parallel
threads. I know sqlite doesn't support concurrent writes, but it does support
parallel reads, so I thought I'd set up a database thread pool of 2-3 threads
and take advantage of whatever parallelism I could get. I thought sqlite would
lock the database during writes and that the other threads would block until it
was unlocked, then proceed. Instead, all other transactions simply failed while
the database was locked. Of course, I could write my own retry logic, but it's
surprising that I would have to. In the end, I settled for just using a
single database thread; it's plenty fast enough for my needs.

One last thing - I love that `diesel` directs the programmer to use database
migrations right from the start. It can be done in Java with tools like Flyway,
but the programmer needs to know to look for them. Explicit, repeatable
migration scripts make databases much easier to work with over long periods of
maintenance.

## Tokio & Reqwest

JARVIS needs to make many HTTP requests to fetch RSS feeds and other resources.
Since they're mostly independent, it's much faster to perform these requests in
parallel. In Rust, that means using `tokio` and `futures`. `tokio` is pretty
low-level, though, and I didn't want to have to add HTTPS support myself, so I
went with `reqwest`'s unstable async API instead, which is a higher-level layer
built on top of `tokio`.

The original Scala code I replaced was also heavily futures-based, so it was
more or less a direct translation. Overall, I was really impressed by this
whole section of the ecosystem. Despite officially being unstable,
`reqwest`'s[^reqwest] async API was well designed, well documented and worked
flawlessly. `futures` is great as well; it provides every combinator I wanted
in a futures library and then some (the `loop_fn` function in particular
cleaned up some ugly recursive code in the original Scala implementation). Note
that I used version `0.1.17` of `futures`; the API has changed a bit in 0.2 and
I understand it will change more in 0.3 which is expected to arrive soon.

[^reqwest]: Wow, that is hard to type. Muscle-memory keeps trying to correct it to 'request'.

I've read comments saying that the `futures` library is hard to learn and hard
to use. Now that I've used it, I don't think that is the case. Almost
everything I know about futures from other languages transfers over quite
cleanly. The only notable difference is that you have to do something with your
future after you've built it. In Java or Scala, you register your callbacks and
then just let the Future object fall out of scope; the callbacks will still be
triggered when the future is completed. Rust's futures need to be polled rather
than notified, though, so you have to build up the future and then submit it to
an event loop to be executed. Once you adjust for that though, the `futures`
API looks pretty much like any other. Maybe it helps that I have extensive
experience working with futures in other languages though. For those who don't,
I believe that the async/await pattern is already available through macros;
that may be more familiar.

That said, it's not all roses. I'm not sure I like how `reqwest` tries to build
a strongly-typed API over HTTP headers. In particular, I have to work with
etags and the last-modified header for caching RSS feeds. I've always treated
them as opaque string tokens, and it's a slight hassle to have to convert
between the typed representation that `reqwest` uses and the string
representation stored in the database. It's just a function call or two,
though; more of a speed bump than an actual problem.

## RSS/ATOM Parsing

Conveniently for me, Rust already has crates for parsing RSS and ATOM feeds -
`rss` and `atom_syndication`. I don't have too much to say about those crates
specifically; they each have a simple job and do it well enough. It might be
nice to have a third crate that provides a basic abstraction over the two
formats (something like the `Rome` library does in Java) but it's easy enough
to just try to parse a response as RSS and then fall back to ATOM if that fails.
Both of these crates are owned by the same GitHub organization, though it seems
like maintenance on the RSS crate is more active.

I would like to comment on one thing tangentially related to these crates
though. They show a problem that I see in a lot of Rust crates, which is that
the documentation is badly cluttered by functions that are not that
interesting. In this case, the feed structures are builders with getters and
setters for all of the various fields used by RSS and ATOM feeds. In other
libraries, it's the `get_ref/get_mut_ref` functions and so on. It can be hard
to visually skim through all of the noise of getters and setters to find the
parsing and creation functions, which are meaningfully distinct. Perhaps RustDoc
or the new doxidize tool could do something to improve the signal-to-noise here,
like allowing the programmer to coalesce together related functions, or to
separate functions into different sections to group the setters and getters
together and the parsing functions in a different section.

## Chrono

My need for date/time operations on this project was thankfully quite limited.
Dealing with dates and times can be unbelievably complicated. In my case, I
mostly just have to check if a day has passed since the last time the user
read a webcomic, or to check if today is a certain day of the week.

That said, I'm not hugely impressed with the `chrono` crate. It did most of the
things I needed it to do, but not quite everything. In particular, it doesn't
appear to have any way to add or subtract large durations (months or years)
from a datetime except to approximate it by using eg. 4 weeks instead of a
month. I fully realize that doing that kind of math correctly is a huge
headache, but `chrono` is the standard (only?) date/time crate in the Rust
ecosystem. People are going to need to do things like this, and if the
ecosystem doesn't provide a standard correct implementation they will invent
their own incorrect versions instead.

Likewise, it lacks a lot of helper functions that I'm used to having from
working with JodaTime, like having an obvious way to get "midnight today" as
a `DateTime`. It's easy enough to piece together from what is there, I suppose,
so I can't say this is a huge problem. The `NaiveDateTime` struct in general is
missing a lot of the features of the `DateTime` struct; if this is intentional
it might be helpful to give clearer guidance to the programmer that they should
convert to a timezone-aware type before operating on it. It would be nice if
Diesel could perform that conversion.

On the plus side; I do like how `chrono` uses a single generic type to
represent the difference between a DateTime in UTC, the local time zone and a
fixed offset. Most other date/time libraries I've worked with use entirely
separate classes for that if they handle it at all.

`chrono` does not appear to have support for the standard `tzdb` database;
there's a separate crate for that, but it doesn't seem to be very actively
maintained and it works by generating fixed Rust code from the database. I
haven't tried, but this would probably make it difficult to deal with changes
to time zones and things like daylight-savings-time rules.

## HTTP Parsing/Scraping

Initially, I wrote all of the scraping code with `select.rs`, then at the last
minute scrapped it all and re-wrote it with `scraper` instead. Overall, I think
both of these libraries are lacking (at least compared to `JSoup`), but they're
lacking different things.

I initially liked `select.rs`' typed selector API, but it currently isn't as
powerful as full CSS selectors simply because a lot of the standard CSS
selectors are not yet implemented. I do like this design, though, because it
makes it easy for the application programmer to extend the system to define
additional selectors of arbitrary complexity. Unfortunately, I have a hard
requirement to allow dynamic, runtime-defined selectors, and `select.rs` does
not support that use case at all right now. Also, `select.rs` is largely
undocumented. It's designed well enough that I was able to figure out how to
use it from the API docs anyway, but it could definitely benefit from some more
effort on documentation.

`scraper`, by contrast, only works with CSS selector strings. This makes it
impossible to extend, but makes it possible for me to use selector strings
provided at runtime. This is a requirement for me because webcomic HTML pages
are super inconsistent from one site to another and hard-coded heuristics for
finding the 'next-page' links can only take one so far. This is why JARVIS
allows the user to override the heuristics and provide a CSS selector string
that matches the appropriate link. Unfortunately, `scraper` does not provide
some of the useful extensions to CSS selectors that `JSoup` does - such as the
`:has(selector)` construction which selects parent nodes that contain descendant
nodes matching the nested selector. The programmer could provide it, but then
we're back to either hard-coded selection behavior or implementing my own extra
parsing.

## Conclusion

The Rust ecosystem is pretty new and unrefined in a lot of places. In
particular, I would like to see improvements made in the areas of date/time
and HTTP parsing/scraping libraries. Meanwhile, `serde`, `tokio/reqwest` and
`diesel` are all already excellent to varying degrees.

As for JARVIS, I've been using the combined Java/Rust version as my daily driver
for about a week now, fixing bugs occasionally. The new version is already much
easier to work on than the old Java/Scala one was. This is all just one more
step in a long-term plan to convert this whole system into a web-app that I can
access from any device without needing to install the software, but for now I'm
going to put this project down and use it for a while until I've ironed out all
of the new bugs. Thanks for reading! I hope this was helpful.
