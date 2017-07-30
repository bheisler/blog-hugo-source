+++
date = "2017-07-30T02:11:19+00:00"
title = "Parsing NES ROM Headers with nom"
description = ""
tags = ["Rust", "nom", "Emulator", "NES"]
categories = ["code"]

+++

Long, long ago (December 2015) I wanted to learn how emulators worked, so I
decided to write an [NES emulator](https://github.com/bheisler/Corrosion).
Not only that, but I opted to write it in Rust, a language which I had never
used before. A crazy idea, to be certain, but once I was done I had indeed
learned a great deal about emulators, the NES, and Rust.

Anyway, I've been working on that project again lately, doing some maintenance work
and upgrades. One of the things I did was rewrite the ROM parser using
[nom](https://github.com/Geal/nom). The ROM parser was the first bit of Rust code
I've ever written, and it was not great, so I thought it was finally time to clean
it up a bit. This post is a short description of that process and my thoughts on
nom as a newcomer to this library. First, a detour to discuss the NES ROM format
- if you're not interested in the fine details, you can skip ahead to the next
section.

## The iNES Header

Nearly all NES ROM files are in one of two formats. There's the
[iNES](https://wiki.nesdev.com/w/index.php/INES) format, or a later extension
called [NES 2.0](https://wiki.nesdev.com/w/index.php/NES_2.0). My existing parser
only supports iNES, and that's all the new parser will support as well. I haven't
come across many ROM's in NES 2.0 format yet, so I haven't needed to add support
for it.

Let's start digging into the iNES header and I'll explain what everything is as
we go. First, we have a four-byte magic number - the ASCII letters 'NES' followed
by 0x1A - the DOS end-of-file character. After that is one byte holding the length
of the PRG ROM data in 16kB blocks and one byte for the length of CHR ROM in 8kB blocks.
NES cartridges contain PRG ROM and CHR ROM. PRG (program) ROM holds the
assembled program code and associated data for the game. It's available in the
main CPU memory map by reading 0x4020 to 0xFFFF, though many cartridges only
support reading PRG ROM at addresses above 0x8000. CHR (character) ROM holds the
graphical data for the game and is only indirectly accessible to the CPU.
CHR ROM is used instead by the PPU (Picture Processing Unit). Some cartridges
have no CHR ROM and instead use CHR RAM, transferring the graphical data
to the CHR RAM at runtime.

After those two bytes are two more bytes of flags. These include various bits
of information about the hardware of the cartridge (eg. whether or not the
cartridge has battery-backed RAM for saving your game). These flag bytes also
contain the mapper ID for the game. Mappers are one of the more... interesting...
aspects of NES emulation. As I mentioned before, the PRG ROM is typically
accessible from 0x8000 to 0xFFFF - a window of 32kB. 32kB is not nearly large
enough for most NES games (some of which have as much as 1MB of PRG ROM alone). To
deal with this, cartridges contain circuit boards called mappers which map
pages of the ROM in and out of the address space. Different games, and especially
games by different manufacturers, often have wildly different mappers. The
emulator must emulate the mapper as well, so the header contains one byte
(split into two 4-bit pieces for historical reasons) containing the mapper ID.

After the first two flag bytes is another page-count byte, this time for PRG
RAM (the battery-backed save RAM in games like Legend of Zelda) and another
flags byte. Finally, we have six reserved bytes, which are not used by iNES but
are used by NES 2.0.

To recap:

* 4-byte magic number
* PRG ROM page count
* CHR ROM page count
* Lower half of mapper number & flags
* Upper half of mapper number & flags
* More flags
* Six bytes of zeroes

Following this header is an optional 512-byte trainer (extra program code added
by some ROM-ripping devices), and the actual PRG and CHR ROM data. Now that we know
what we're parsing, let's take a look at nom.

## nom

The way parsing works in nom is you use the do_parse! macro to define your
parser, and a number of other functions and macros to define the structure of
your data. These macros and functions collectively generate some Rust code which
parses that data and returns one of three possible results - Done (containing any
remaining, unparsed data and the resulting value), Incomplete (meaning more
data is needed) or Error (meaning the data is invalid or otherwise couldn't
be parsed). The use of macros for this is a rather clever idea, though not
without downsides.

One of those downsides is that the compiler can't really help you when you
make a mistake. For instance, it took me longer than I'd like to admit to get
the following code to compile before I realized that I had forgotten to pass
the input to the do_parse macro.

{{< gist bheisler 2fae3b00eedcb80a1a109e622a55f74f >}}

Once I got going though, it was pretty smooth sailing and extremely fast to
parse out the rest of the header and construct my Rom structure. The tag!
macro takes a given sequence of bytes and reads that sequence from the input.
be_u8 (the 'be' means big-endian) is a one-byte unsigned integer. Then we have
the cond! macro, which applies a given parser if some condition is true, and
finally the take! macro, which consumes a given number of bytes and returns
them as a slice.

{{< gist bheisler a39a0fdd5b1741ce7982849febe914c8 >}}

Since my code doesn't support the NES 2.0 extension, I wanted to detect if a ROM
was using that format and return an error. This is where I started to run into
trouble; I couldn't find an obvious way to conditionally return an error.
I ended up working around it by using the call! macro to call a function I wrote
which would return an error if the ROM was in NES 2.0 format. This was somewhat
surprising to me; this seems like it would be a common problem.

{{< gist bheisler 68c917c9f44934dd848b0efa61e7dbdd >}}

At this point, I had a working parser, but I decided to take the opportunity to
rework my code a bit as well. Previously, I simply stored the flag bytes in the
Rom structure and left it to other code to mask out the individual flags, as well
as the two 4-bit pieces of the mapper ID. nom can parse individual bits out of
the input as well, so I started with separating out the mapper ID from the rest
of the flag bytes.

nom overall could use some work on its documentation, but using the bit-indexing
is particularly opaque. I had to look up a cached version of an old blog post
([link](https://webcache.googleusercontent.com/search?q=cache:4CNayFlPRicJ:siciarz.net/24-days-rust-nom-part-2/+&cd=1&hl=en&ct=clnk&gl=ca))
to find out how to do it. To spare you the same trouble, here's a quick overview.

The bits! macro takes a bit-stream parser (eg. take_bits!) or a type-agnostic
parser (eg. tuple!) and generates the code to apply that parser to a byte-slice
input. There is also a bytes! macro to go the other way, applying a byte-slice
parser to a bit-stream input. Inside the bits! macro, you can use parsers that
consume individual bits. When switching from bit-stream to byte-slice parsing
(that is, at the end of the bits! macro or the beginning of a bytes! macro), if
there's a partial byte remaining in the input it will be ignored and the
subsequent byte-slice parser will start parsing at the next whole byte. The only
two built-in bit-stream parsers are take_bits! (which consumes a given number
of bits from the input, and assembles them into the given integer type) and
tag_bits! which is like tag! but for bits.

Unfortunately, at this point it isn't possible to give names to each value in
a bits! macro like it is in do_parse!, so I had to make do with collecting the
mapper ID bits and the flag bits into a tuple instead.

{{< gist bheisler 30d84186661c04a6d383278a18199e34 >}}

I went on to make some further changes, but they're not related to nom so I'll
skip the details. You can take a look at the [code](https://github.com/bheisler/Corrosion/blob/fdc4fa0334aabaa76518479dd0ad3e62e4e5ebb1/src/cart/ines.rs)
if you're interested.

## Impressions of nom

I kind of like nom. There's a rocky learning curve, and the documentation needs
some work. I'm also a bit wary of such heavy use of macros. Parsing is (often)
not performance-critical, so I'd be willing to sacrifice some runtime efficiency
to get some more help from the compiler when I make mistakes. On the other hand,
once you do get the hang of it, it's quick and easy to define parsers for quite
complex data structures and the code reads a lot like a description of the format
to be parsed, which is always nice. nom has some beautifully clear example parsers
to look at (take [this GIF parser](https://github.com/Geal/gif.rs/blob/master/),
for example). It works on both binary and text data as well, which is a plus.

Overall, I would consider nom for future projects that involve parsing data. The
lack of documentation could cause some headaches, but it's much easier and safer
to use a battle-tested library like nom than it is to write your own hand-written
parser for the same data.

If you'd like to check out the code or play around with some perfectly legal,
homebrew NES software, you can find it on
[Github](https://github.com/bheisler/Corrosion).
