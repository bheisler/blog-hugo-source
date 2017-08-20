+++
date = "2017-08-10T19:00:20-06:00"
title = "Experiments In NES JIT Compilation"
categories = ["code"]
draft = true
tags = ["Rust","Assembly","NES","JIT","Emulator"]

+++

Inspired by the always-incredible work on [Dolphin](https://dolphin-emu.org/),
I decided to write myself an [NES emulator](https://github.com/bheisler/Corrosion)
called Corrosion a couple years ago. I managed to get it working well enough to
play basic games, and then put the project aside. This post is not about the
emulator itself, but rather the JIT compiler I added to it last year and the
upgrades to said JIT compiler I've made over the past few weeks.

Having read that, you might be wondering "Why would anybody write a JIT compiler
for the NES?" Indeed, it's a reasonable question. Unlike newer consoles, it's
quite feasible to emulate the NES's modified 6502 CPU at full speed with a
simple interpreter. As with most of the projects I write about here, I wanted
to know how they work, so I built one. Having done so, I can say that I would
not recommend JIT compilation for production-quality NES emulators except in
severely resource-constrained environments. However, I would strongly recommend
this project for anyone who wants to learn more about JIT compilers, as it's
complex enough to be challenging but simple enough to be manageable.

This is more of a post-mortem article covering the design of my JIT compiler,
the pitfalls I ran into and the mistakes I made in construction and what I've
learned from the process. It is not a tutorial on how to write your own JIT
compiler, though there are some links that cover that in more detail at the end.
The emulator is written in Rust, but you don't need to know Rust to follow along.
Most of the concepts will map to other low-level languages like C or C++. An
understanding of x64 assembly would be helpful, but again, not required - I
didn't know much assembly starting this project, and even now my assembly is
pretty weak.

## Basics of JIT Compilation

Just to make sure everyone's on the same page, a quick interlude on how JIT
compilers work at a high level. If you're familiar with this already, feel free
to skip ahead.

Broadly speaking, a JIT (or just-in-time) compiler is a piece of code that
translates some kind of program code into machine instructions for the host CPU.
The difference between a JIT compiler and a regular compiler is that a JIT
compiler performs this translation at runtime (hence just-in-time) rather than
compiling the code and saving a binary for later execution.
For emulation, the original program code is typically the binary machine code
that was intended for the emulated CPU (in this case the NES' 6502 CPU). However,
JIT compilers are used for many other kinds of programs. Examples include the
JIT compilers used by modern browsers to run Javascript, the Hotspot compiler
in the JVM and dynamic language runtimes like PyPy and LuaJIT.

JIT compilers are used primarily to speed up execution. A standard interpreter
must fetch, decode and execute instructions one at a time. Even in a relatively
fast language like Rust or C, this incurs some overhead. A JIT compiler, on the
other hand, can be run once and emit a blob of machine code which executes an
entire emulated function (or more) in one sequence of instructions. Eliminating
that overhead often greatly improves execution speed. However, since the
compilation is done at runtime, care must be taken that the JIT compiler itself
doesn't run slowly enough to cause performance problems, where an ahead-of-time
(AOT) compiler can spend much more time optimizing the code it generates.

A JIT compiler typically parses some chunk of code, performs any analysis
it needs to, and then generates binary machine code for the host CPU into a
code buffer. Modern OS's require these code buffers to be marked as read-only
and executable before they can be executed, but once this is done the generated
code can be executed by jumping the host processor to the beginning of the buffer
just like any normal function. Some more sophisticated JIT compilers will
translate the source language into some intermediate in-memory representation
for further processing before emitting the final machine code.

As a simple example, consider the following 6502 code:

    LDA $1A  // Load byte from RAM at 0x001A into A register
    ADC #$20 // Add 0x20 to the A register
    STA $1A  // Store A register into RAM at 0x001A

This might be translated into the following (simplified) x64 code:

    MOV r9b, [rdx + 1Ah] // Load byte from RAM array pointed to by rdx into r9b
    ADC r9b, 20h         // Add 0x20 to r9b, which represents the A register
    MOV [rdx + 1Ah], r9b // Store the result back into the RAM array at 0x001A

Note that I've omitted things like processor flags and interrupts from this
example.

## Design of Corrosion's JIT

Corrosion has a relatively simplistic JIT compiler. It has no intermediate
representation or register allocator, which might be found in more sophisticated
JIT compilers - Dolphin's PPC JIT has a register allocator, while David Sharp's
Tarmac ARM emulator features an IR called Armlets (see links at the end).
Since machine code is typically a binary format too complex for humans to write
directly, most JIT compilers also devote much code to translating some
assembly-like syntax or DSL used by the developers into the bytes that are given
to the host CPU. Fortunately for me, there is an extremely useful compiler plugin
by CensoredUsername called [dynasm-rs](https://github.com/CensoredUsername/dynasm-rs)
which can parse an Intel-assembly-like syntax and perform most of the assembly
at compile time. I would recommend any Rust-based JIT compiler author should
check out this plugin; I've found it to work well, with no bugs to speak of and
CensoredUsername was very helpful about answering my silly questions when I asked.
The only limitation is that it currently only supports the x64 instruction set,
though x86 support is planned. For those who prefer C/C++, there is a similar
tool called [DynASM](https://luajit.org/dynasm_features.html), though I can't
comment on that as I've never used it myself.

{{< gist bheisler a949bf7d08573e4529b4a9e2fd10f5e6 >}}

The entry point to the JIT compiler in Corrosion is the
[dispatcher module](https://github.com/bheisler/Corrosion/blob/develop/src/cpu/dispatcher.rs).
When the CPU interpreter detects that it's executing an address from the ROM,
it makes a call to the dispatcher to compile (if necessary) and execute the
relevant block of code. The dispatcher is responsible for managing the cache
of generated code blocks and calling to the JIT compiler to generate more code
when necessary.

If the dispatcher doesn't have an existing generated code block for a particular
location in ROM, the [nes_analyst module](https://github.com/bheisler/Corrosion/blob/develop/src/cpu/nes_analyst.rs)
is used to collect information about the code to be compiled. The primary
responsibility of nes_analyst is to determine where the end of the current
function is and collect information about the instructions it contains.
This is done using a very simplistic algorithm that I copied from Dolphin. It
decodes instructions until it finds the first unconditional exit point (eg.
returns, jumps or calls to other functions). To ignore the conditional exit
points, it tracks the target address of the farthest forward-facing branch it's
seen; any exit point before that is conditional. This approach does occasionally
overestimate the length of the actual function, but it's simple and fast.
The nes_analyst module is also responsible for identifying which instructions
are the targets of branches and which instructions change or use which processor
flags, which is used later in the compilation process. Decoding opcodes is done
using the `decode_opcode!` macro which expands to a giant match structure that
calls the appropriate functions. `decode_opcode!` has handling for the various
addressing modes which we don't really need here, so there is some clutter,
but it works well enough.

As mentioned earlier, Corrosion doesn't have a register allocator. It's quite
common for emulated CPU's to have more registers than the host CPU, especially
since many JIT compilers run on the relatively register-light x86
and x64 instruction sets. As a result, they need to do the extra step of
determining which emulated registers should be represented by host registers
and which should be stored in memory at any given point in the code. Conveniently,
the NES's 6502 CPU has even fewer registers than x64 does, which means we can
statically assign one x64 register to represent each 6502 register and have a
few left over to store things like the pointers to the Rust CPU structure and
the array which stores the emulated RAM, as well as a few more for general-purpose
scratch memory.

Most 6502 instructions come in various different flavors called addressing modes,
which control where they take some of their data from. Take the CPX (ComPare X)
instruction as an example. This instruction compares the value in the X register
to a one-byte operand, setting the N (sign), Z (zero), and C (carry) flags.
If the opcode is 0xE0, the operand is a one-byte immediate value stored
right after the opcode. If the opcode is 0xE4, the next byte is instead 
zero-extended to 16 bits and used as an address into RAM. This mode is called
the zero-page mode, and it can only access the first 255 bytes of RAM, which are
called the Zero Page. The byte at the selected location is used for the
comparison. Finally, if the opcode is 0xEC, the next two bytes (little-endian)
are used as an absolute address into memory and whichever byte they select is used.
If you're wondering, zero page instructions are one byte smaller and slightly
faster than absolute instructions, which matters when you have a 64k address
space and 1.34MHz CPU.

There are a number of other addressing modes, but this should suffice to explain
the concept. I could have written hand-tuned machine code for all 255 possible
opcodes, but I'm a lazy programmer, so instead I wrote a collection of routines
that generate code to move the appropriate byte into one of my scratch registers
(r8). That way, I can call the routine appropriate for the addressing mode to load
the operand into r8, then define the instruction code to take it from there.
Likewise, when writing to memory, I can move the value to be written into r8
and call a routine to generate the instructions to transfer that value into the
appropriate location in memory. It's slightly less efficient at runtime because
I have to move data through an intermediate register instead of using it
directly, but it saved a lot of my time.

Slight aside - I was a bit surprised by how small the difference is between
writing code to implement something and writing code that generates a program
to implement something. I'll use CPX as an example again - this is some code
from an earlier version of the JIT:

{{< gist bheisler eebebbacefda3c626f597a6c865805dd >}}

If I were actually writing this in assembly, this reads like pretty much how
I'd do it - call the function for the appropriate addressing mode to load the
operand, do some branching to set or clear the carry flag, compare the operand
against the X register and call some functions to update the sign and zero
flags. In fact, that's exactly how the interpreter handles this instruction.
Instead, I'm calling a function to generate the code to load the operand,
generating code to do the comparison and update the flags, etc. Despite that
extra layer of indirection, though, it reads pretty much the same. Because
of this, implementing all of the instructions was as straightforward as
translating my Rust code into assembly. I'm not actually that good with
assembly, so my code will probably make experienced assembly programmers cry.
Still, it does the job. With that said, I would be interested in ideas for
making it better if anyone would care to share links or suggestions.

## Enhancements

That brings me up to the present, more or less. Over the past few weeks I've
been working on some 'optimizations' to the JIT compiler. I write that in quotes
because for the most part I can't actually detect any measurable change in
execution speed for these, but they were somewhat interesting to implement.

The first such enhancement that I added was redundant flag elimination. This was
actually really easy and I probably should have done it from the start. The idea
here is that a good chunk of the code emitted by a JIT compiler (at least for
emulators) does nothing but implement the various flag behaviors of the emulated
CPU (eg. setting the overflow flag when an addition overflows). To some extent,
a clever JIT compiler author can exploit similar flags in the host CPU to
accomplish this with fewer instructions, but it's still there. If you look at
[documents detailing the 6502's instruction set](http://www.oxyron.de/html/opcodes02.html),
you'll quickly see that many instructions change the flags in some way,
but very few instructions use them. What this means is that a typical program
will overwrite processor flags far more often than they're actually used.
Interpreters sometimes take advantage of this by not storing the flags at all,
and instead storing enough data to calculate the flags and then evaluating them
lazily when needed. A JIT compiler, however, can go one step further and analyze
every instruction to see if that flag value will be used before it's overwritten
by another instruction. If not, it doesn't emit the machine code to update the
flag.

The way I implemented this is to have nes_analyst keep track of the last
instruction to change each flag while it's stepping through a function. Then
when it hits an instruction that uses a flag, it looks up the InstructionAnalysis
structure for the last instruction to set the flag, which contains a set of
booleans indicating whether each flag will be used. Since we now know that that
instruction's flag will be used and not overwritten, we set the appropriate
boolean to true, signaling the JIT compiler to emit code to update that flag
later on.

There are a few pitfalls with this approach. For instance, if a branch is taken
or if execution hits a jump instruction, we can't know if the code it jumps to
will rely on this flag. If so, this optimization could break. A more
sophisticated analysis could probably detect that, for at least some cases.
This one-pass algorithm can't, so to be on the safe side it assumes that jump
and branch instructions use all of the flags. Likewise, when an interrupt
occurs, the NES pushes the flags and the return address on the stack. Since an
interrupt can occur at any time, there's no way to be sure that the flags byte
it pushes on the stack will be correct. I don't have a solution to this except
to assume that no game will break because of the exact value of the flags byte
on the stack. This seems like a safe assumption. Since interrupts can happen at
any time, it would be difficult to know what the flags should have looked like
when the interrupt happened. Something to be aware of, though.

The initial version of my JIT compiler emitted a fixed series of instructions
(a function prologue) at the beginning of every compiled block which rearranged
the arguments from the win64 calling convention and loaded all of the NES
register values out of memory into the designated x64 registers. Then, at every
possible exit point from the block, it would emit some code (the epilogue) to
do the reverse; store the register values back in memory and return control
back to the interpreter. This means we can't just jump to the middle of a
compiled function - we'll skip over the prologue and crash. Therefore, if some
other code tries to jump into the middle of a function, we need to compile that
function suffix as a complete function of its own, with its own prologue and
epologues. Also, these duplicate prologues and epilogues take up space in the
instruction cache, which could reduce performance.

Instead, I've changed it to use a trampoline; this is an ordinary Rust function
taking the pointer to the compiled code to jump to as well as the pointers to
the CPU structure and the RAM array. It contains an `asm!` macro which defines
the assembly instructions to load the registers from memory, call the compiled
block and then store the updated registers back into memory. Since we now only
have one global 'prologue/epilogue' shared between all compiled code blocks, we
can then call directly into the middle of an existing block with no trouble.

Another problem with the prologue/epilogue design was that compiled blocks
couldn't easily call each other; the JIT would have to store everything back in
memory to prepare for the prologue to be run again, or know how to jump past
the prologue or something else complicated. With a trampoline-based design,
it's easy to jump to another block - everything's already loaded into the
appropriate registers, so you can just jump the host processor to the beginning
of the target block. One wrinkle is that you need to be careful not to link
together blocks from different banks of ROM, since one bank could be switched
out and now your code is jumping to the wrong place.

## Challenges

Speaking of that trampoline function, I did run into some difficulty implementing
it. The trampoline function needs to transfer values from a struct in memory
to and from registers. It takes a pointer to a CPU struct as an argument, but
that alone isn't enough; Rust can rearrange and pad the fields however it likes,
so I needed a way to get the offset of each field from the pointer to the CPU.
C/C++ programmers can use the offsetof macro, but Rust has no official way to
calculate the offset of a field within a structure. The layout of Rust structures
isn't even guaranteed to be the same from release to release - in fact, it [was
changed](http://camlorn.net/posts/April%202017/rust-struct-field-reordering.html)
just a few months ago in version 1.18.  I could have marked the CPU struct with
`repr(C)` to force it to use the C layout and used hard-coded offsets, but that
felt inelegant. I would have needed to update the offsets every time I modified
the CPU struct, for one thing. Instead, I found a macro online that can calculate
the offset of any field in a structure.

{{< gist bheisler b21c9bfc07ee4c1afac2e96ef55dfffd >}}

This works by casting 0 (NULL) to a raw pointer to a `$ty` structure,
dereferencing it, taking a reference to the field and casting that pointer back
to a usize. As far as I can tell, this is actually safe and should be entirely
evaluated at compile time, but it still needs to be wrapped in an unsafe block
anyway. Use at your own risk, etc. etc. It's pretty easy to add more macros to
calculate offsets with multiple levels of nesting - see `offset_of_2` in
`x86_64_compiler/mod.rs` for an example. One drawback of this is that it can't
be used for static values - it's forbidden to dereference null pointers when
initializing static values, even with unsafe. Because of that, I didn't think
it would work with the `asm!` macro's `n` value constraint (meaning constant
integer) but it totally does. Still, it'd be really nice if this was something
Rust supported out of the box.

Another challenge I ran into while implementing this is dealing with some
quirks of the win64 calling convention. Rust, you see, does not have a defined
calling convention, so there's no reliable way to call directly into Rust code
from assembly. Instead, you expose a function marked `extern "win64"` or
similar which then calls the function you actually want. This way, you set up
your code to be compatible with the chosen calling convention - pushing
caller-saved registers on the stack, placing arguments in the right registers -
and leave Rust to handle the translation to its own internal calling
convention. The win64 convention is one of two 64-bit calling conventions
supported - the other one, sysv64, is still experimental and requires a special
feature flag even on nightly. The JIT compiler needs to call back into Rust
code to handle things like reading and writing memory-mapped devices like the
PPU or the controllers. Unfortunately, win64 is slightly difficult to work
with. It requires that the stack pointer be 16-byte aligned at the entry to
every function, and that the caller provide a 32-byte empty space on the stack
before the return address for the callee to use as scratch space. Failure to do
this correctly causes hard-to-debug segfaults. In my code, I don't have many
places where I call back to Rust code, and the generated code doesn't use the
stack very much, so I deal with this by just hard-coding the number of bytes of
space to leave on the stack. It's not ideal (if I had more complex requirements
I might add a trampoline_to_win64 function to match trampoline_to_nes), but
other JIT compiler authors should be aware of it.

Next up, debugging. Debugging a JIT compiler sucks even more than debugging an
interpreter. Debugging tools largely just don't handle runtime-generated
machine code. Visual Studio, despite having a quite competent disassembly view,
just will not step into a generated code block. GDB's disassembly view will at
least display the generated code and let you scroll downwards through it, but
not back upwards (I guess because it doesn't know which byte to start
disasembling from, but it could at least allow you to scroll back up to the
program counter). GDB also fails to insert breakpoints into generated code
blocks even when you give it the address of the instruction to break at. GDB
has some sort of interface for exposing debugging info for JIT-compiled code,
but I wasn't able to make much sense of it. Apparently it relies on the JIT
compiler generating and emitting a complete ELF table in memory for the
generated code, which sounds like a lot of hassle. Anyway, in the absence of a
debugger, good old println-debugging is your best friend. This is complicated
by the fact that you have to insert your debug output into the generated code
at runtime, but I'd strongly suggest you find a way. I wish I had done this
earlier, it would have saved me a ton of debugging time.

Handling interrupts also proved to be something of a challenge. The NES has
very tight synchronization between the CPU and the other hardware, which
includes interrupts. I had hoped there would be some clever way to implement
interrupts without just checking if there had been an interrupt before every
emulated instruction, but I couldn't find one. This is part of why the
duplicate epilogues were a problem, in fact; every emulated instruction was
preceded by an implicit exit point, so there were a lot of redundant epilogues.
The best I could come up with was to store a cycle count representing when the
next interrupt would occur and then compare that against the actual cycle count
before every instruction. This sort of works, because the hardware interrupts
of the NES are entirely predictable, but it probably wouldn't work for other
systems. On the other hand, other systems probably don't require such tight
timing for the interrupts, so if you're writing a JIT you might be able to get
away with only checking for interrupts once every 10 emulated instructions or
something.


As I mentioned in my post on [parsing iNES ROM headers](/post/nes-rom-parser-with-nom/),
the NES only has 32k of address space mapped to the ROM. Some games take up
more than a megabyte of ROM space, so NES cartridges incorporate circuitry so
that the game can map banks of the ROM in and out of the address space.
Implementing the bankswitching logic is one thing, but this allows for the
possibility of self-modifying code even if you only use the JIT compiler when
executing from ROM. There are all sorts of wacky corner cases this enables -
what if the bank you're executing is switched out between instructions? What if
half of a block is on one bank and the other is on the next bank, then the
second half gets switched out? If you then execute a generated code block that
compiled in the instructions from the original bank, the game will probably
break. You could even have a multi-byte instruction on a bank boundary, such
that the last byte of the instruction depends on which bank is mapped in. I'll
be honest, I didn't solve this problem. Corrosion just assumes that no game
will do strange stuff like this. Initially, I took a much more conservative
approach and deleted all of the compiled code for a bank whenever it was
switched out. This was a mistake; games like Legend of Zelda bankswitch
frequently enough that the emulator was constantly recompiling sections of code
that it had already compiled before. Major respect for the developers of other
JIT-based emulators - dealing with arbitrary self-modifying code, especially in
situations where you have an instruction cache and/or pipelining, must be a
nightmare.

## Other resources & conclusion

Well, that's about it from me. This was a bit more stream-of-consciousness than
my posts usually are, since I was writing about something I made a while ago.
I normally write my posts concurrent with working on the projects they cover.
I hope you found it interesting and/or educational. I'll leave you with some
links to other resources that I used or wish that I'd known about when I was
building this thing.

First off, Eli Bendersky's Adventures In JIT Compilation series 
([Part 1](http://eli.thegreenplace.net/2017/adventures-in-jit-compilation-part-1-an-interpreter/),
[Part 2](http://eli.thegreenplace.net/2017/adventures-in-jit-compilation-part-2-an-x64-jit/),
[Part 3](http://eli.thegreenplace.net/2017/adventures-in-jit-compilation-part-3-llvm/),
[Part 4](http://eli.thegreenplace.net/2017/adventures-in-jit-compilation-part-4-in-python/))
is an excellent introduction to the low-level details of implementing an
interpreter and a series of JITs for Brainfuck, including different ways of
generating machine code, intermediate representations and so on.

Second, David Sharp's [report on Tarmac](http://www.davidsharp.com/tarmac/tarmacreport.pdf),
an optimizing JIT compiler for ARM emulation. It's over a hundred pages long,
but this is an excellent overview of JIT compilation techniques as well as a
detailed explanation of how Tarmac works. Sharp gives a good explanation (often
including diagrams and/or examples) of common approaches to various problems in
emulation, even if Tarmac itself doesn't use them. If nothing else, read it to
learn about terminology you can plug into a search engine to find out more.

If you're interested in NES emulation in particular, [the NESdev wiki](
    http://wiki.nesdev.com/w/index.php/Nesdev_Wiki
) is the premiere source of information for aspiring emulator developers and 
homebrew ROM authors. This wiki and the resources it links to (including 
[the forums](http://forums.nesdev.com/), 
[test ROMs](https://wiki.nesdev.com/w/index.php/Emulator_tests), and lots
of documentation about the CPU/PPU/APU) provided all of the documentation I used
to build this emulator in the first place.

Finally, Dolphin's JIT doesn't seem to have much documentation, so if you want
to find out more about it there are only two sources that I've found useful.
The [source code](https://github.com/dolphin-emu/dolphin/tree/master/Source/Core/Core/PowerPC),
and [this Reddit comment](https://www.reddit.com/r/emulation/comments/2xq5ar/how_close_is_dolphin_to_being_cycle_accurate/cp318ka/)
by one of the developers giving a relatively high-level overview of how it all
works.

This has been a fun project. I have some other stuff in the pipeline at the
moment, but I'd like to come back to this emulator at some point. Until next
time...
