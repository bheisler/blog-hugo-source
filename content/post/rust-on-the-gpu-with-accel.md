+++
date = "2018-06-14T19:00:00-06:00"
title = "Running Rust on the GPU with Accel"
tags = ["Rust", "GPGPU", "Accel"]
categories = ["code"]
author = "Brook Heisler"
+++

NOTE: Much of what I discuss below is no longer accurate.

For the past month or so, I've been working on a follow-up to my series on [Writing a Raytracer in
Rust](/post/writing-raytracer-in-rust-part-1/). This time around, I'll be talking about writing a
GPU-accelerated Path Tracer. As always, I'm writing it in Rust - including the GPU kernel code.
Compiling Rust for GPUs at this point is difficult and error-prone, so I thought it would be good
to start with some documentation on that aspect of the problem before diving into path tracing.

I've used [Accel](https://github.com/termoshtt/accel) for this project because it's probably the
best option currently available. "Best available" sadly does not imply that it's production-ready
at this point, but we'll make do where we have to. Accel's author, Toshiki Teramura, has already
merged several of my pull requests making various improvements to the library. Unfortunately, some
of the problem spots lie lower down, in rustc or even in LLVM's PTX backend.

I will assume that you are at least somewhat familiar with CUDA programming. If you aren't, there's
a very good Udacity course on the subject that was posted to Youtube [here](https://www.youtube.com/playlist?list=PLGvfHSgImk4aweyWlhBXNF6XISY3um82_).

## Installing Prerequisites

Accel requires a number of things pre-installed on the system before it can compile and execute GPU
code, so let's start there. First, you'll need to download and install the [CUDA
toolkit](https://developer.nvidia.com/cuda-downloads) for your system. This is pretty 
straightforward (at least on Windows) so I'll just move on.

Second, you'll need to install Xargo for cross-compilation. I understand the Rust team is planning
on integrating Xargo's functionality into Cargo, but at time of writing that hasn't landed yet. In
the meantime, this is as simple as `cargo install xargo`. You'll also need a Nightly version of Rust,
so grab that with `rustup install nightly`.

Third, you'll need some of LLVM's tools - specifically, `ar`, `llvm-link` and `llc`. On Linux (I
did this on Arch, your distro may vary) this was pretty easy - I just installed the `llvm` package
and all of these tools were included. However, LLVM's Windows installer does not include them, so
we have to build them from source. This is... an involved process. The process is detailed
[here](https://llvm.org/docs/GettingStartedVS.html), but I'll try to summarize as best I can. This
is what worked for me, but your milage may vary, caveat emptor, the usual. I'm not an LLVM guru so
I probably won't be able to help much if things go wrong.

To build LLVM, you'll need to download and install [Visual
Studio](https://www.visualstudio.com/downloads/) (2015 or later, I used 2017) and
[CMake](https://cmake.org/download/). Visual Studio does seem to be required - LLVM apparently
cannot be built by LLVM on Windows. Open Visual Studio and create a C++ project, which should cause
it to automatically download and install the C++ tools (you can delete the project afterwards).
Then download and unpack the LLVM source from [the download page](https://releases.llvm.org/download.html).

Open the CMake GUI and set the path to the source directory. Also, set up the build directory -
note that this is NOT where the final binaries will be placed - I think it's a temporary directory
used during the configuration and compilation process, and this is where the Visual Studio project
files will be generated. It doesn't really matter what you set the build directory to, so make it
easy to find later. Click Configure. In the window that appears, set the toolset to `host=x64`
(assuming that you're on a 64-bit CPU, which you probably are. If not, I think you should leave
this blank, but I'm not sure.) Click Finish and wait for a while. At this stage, you may want to
find `CMAKE_INSTALL_PREFIX` in the list of options and set it to point to somewhere else - this is
where the final binaries will be found. Finally, click Generate, and CMake will generate a Visual
Studio Solution file ("LLVM.soln") in your build directory.

Open that in Visual Studio and press F7 (or click Build->Build in the menu) to begin the
compilation process. This process took over an hour on my machine and rendered it largely unusable
in the meantime due to high memory usage, so you'll want to be aware of that (close memory-hungry
applications like web browsers). Once that is finished, you'll have the necessary executables in
`$CMAKE_INSTALL_PREFIX/bin`. You can now go ahead and clean up the CMake build directory (it takes
up a lot of disk space) and even uninstall CMake at this point; we won't be needing it anymore.
Likewise, if you like, you no longer need to have the LLVM source code either.

OK! Now we have everything installed and we're almost ready to run some code on the GPU. Make sure
that you've added your new LLVM tools to your `$PATH`. Also, set the environment variable
`CUDA_LIBRARY_PATH` to tell Accel where to find the CUDA libraries (in my case, I set it to
`C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v9.1\lib\x64`).

You will probably want to clone the Accel repository as well; some of the latest fixes haven't been
released yet and I found I needed to make some custom modifications to it to get it to compile.

```
git clone https://github.com/termoshtt/accel.git
```

Specifically, I needed to modify `nvptx/src/compile.rs` to remove the `+nightly` argument to Xargo.
I haven't submitted a pull request for this because I'm unsure if that change would work for others
or if it's just an oddity of my own environment.

Finally, we can start writing some Rust!

```
cargo init cuda-test
cd cuda-test
rustup override set nightly
```

## Basic Example

Paste the example code from the Accel repository README into the `src/main.rs` file, and add the
following to the `Cargo.toml` (assuming you cloned Accel as I suggested):

```
[dependencies]
accel = { version = "0.1.0", path = "../accel"}
accel-derive = { version = "0.1.0", path = "../accel/accel-derive"}
```

You'll want to edit the `#[build_path]` attribute on the `add` function though. The way Accel works
is it uses a procedural macro to copy your kernel code into a second crate and compiles that crate
to produce a PTX file which it can then load and provide to CUDA. By default, the example places the
crate in a hidden folder under your home directory, which is just messy.

At this point, you should be able to `cargo run` and see the following output:

```
a = [0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0, 11.0, 12.0, 13.0, 14.0, 15.0, 16.0, 17.0, 18.0, 19.0, 20.0, 21.0, 22.0, 23.0, 24.0 25.0, 26.0, 27.0, 28.0, 29.0, 30.0, 31.0]
b = [0.0, 2.0, 4.0, 6.0, 8.0, 10.0, 12.0, 14.0, 16.0, 18.0, 20.0, 22.0, 24.0, 26.0, 28.0, 30.0, 32.0, 34.0, 36.0, 38.0, 40.0, 42.0, 44.0, 46.0, 48.0, 50.0, 52.0, 54.0, 56.0, 58.0, 60.0, 62.0]
c = [0.0, 3.0, 6.0, 9.0, 12.0, 15.0, 18.0, 21.0, 24.0, 27.0, 30.0, 33.0, 36.0, 39.0, 42.0, 45.0, 48.0, 51.0, 54.0, 57.0, 60.0, 63.0, 66.0, 69.0, 72.0, 75.0, 78.0, 81.0, 84.0, 87.0, 90.0, 93.0]
```

You have now run Rust code on your GPU! Now, I'll walk through what this code is doing.

```
#[kernel]
#[crate("accel-core" = "0.2.0-alpha")]
#[build_path(".rust2ptx")]
pub unsafe fn add(a: *const f64, b: *const f64, c: *mut f64, n: usize) {
    let i = accel_core::index();
    if (i as usize) < n {
        *c.offset(i) = *a.offset(i) + *b.offset(i);
    }
}
```

This declares our kernel - the entry-point function that will be launched on the GPU, distinguished
by the `#[kernel]` attribute. This code will be copied to the `lib.rs` file of a separate crate (in
this case, located at the path `.rust2ptx`), compiled to LLVM bitcode, linked together with the
bitcode of all dependencies and finally compiled again to produce a PTX file that CUDA can accept.
You can add dependencies to this subcrate using the following attributes:

```
#[crate("accel-core" = "0.2.0-alpha")]
#[crate_path("common" = "../common")]
```

The `#[crate]` attribute is for regular Crates.io crates, while the `#[crate_path]` attribute
refers to a crate by directory path. Note that this path is relative to the temporary kernel
directory (`.rust2ptx`), hence the leading `..` (in this case, that means `.rust2ptx/../common`, or
just `common`). There is no way to add `use` statements to the generated `lib.rs` file, so you'll
need to refer to parameters with their fully-qualified type, though you can add `use` statements
inside the kernel function if you wish.

This simple example uses the `accel_core::index()` function to get the thread index, which works
for simple kernels but for anything more complicated you'll probably want to use the
`thread_idx/block_dim/block_idx/grid_dim` functions which return a structure containing the
relevant values for all three dimensions (or just call the compiler built-ins directly - see the
[`accel_core` rustdoc](https://docs.rs/accel-core/0.2.0-alpha/accel_core/) for more details).

```
fn main() {
    let n = 32;
    let mut a = UVec::new(n).unwrap();
    let mut b = UVec::new(n).unwrap();
    let mut c = UVec::new(n).unwrap();

    for i in 0..n {
        a[i] = i as f64;
        b[i] = 2.0 * i as f64;
    }
    println!("a = {:?}", a.as_slice());
    println!("b = {:?}", b.as_slice());
```

Here, we allocate and fill three `UVec`s. These are fixed-size arrays in a [Unified Memory](https://docs.nvidia.com/cuda/cuda-c-programming-guide/index.html#um-unified-memory-programming-hd)
space shared between the CPU and GPU. In Accel, this is how you bulk-transfer data to and from the
GPU's memory and allocate working memory space for the kernel.

```
    let grid = Grid::x(1);
    let block = Block::x(n as u32);
    add(grid, block, a.as_ptr(), b.as_ptr(), c.as_mut_ptr(), n);

    device::sync().unwrap();
    println!("c = {:?}", c.as_slice());
```

Here, we create Grid and Block structures to define the size (Block) and number (Grid) of our
thread blocks in one, two, or three dimensions. This is analogous to the parameters in the `<<<>>>`
syntax in CUDA C. We launch the `add` kernel on the device by calling the `add` function, passing
first our grid and block settings, then the actual parameters to the function (converting UVecs to
raw pointers). Finally, we call `device::sync()` to block the current thread until all of the
kernels we've launched have completed, then we print the results.

At this point, I think it's useful to talk a bit about how to design a Rust GPU project. Accel's
procedural macro can really only handle a single function, and that's not enough to build anything
interesting. However, it does know about crates. You'll definitely need the `accel-core` crate - it
provides access to compiler built-ins like the `threadIdx` values which are necessary for GPU
programming. I think it's also useful to put the majority of your code into a second sub-crate in a
local subdirectory. This makes it easy to share common structures and functions between your GPU
and CPU code, and even execute the kernel on the CPU for debugging and testing purposes. In my path
tracer, the `#[kernel]` function is nothing more than a simple wrapper around my actual kernel
function which is defined in a separate crate. If you do this, however, note that rustc will not
inline functions from one crate into another unless they're tagged with `#[inline]`, which can ruin
the performance of your kernel. Handily, the generated PTX file is plain text, so if you're familiar
with reading assembly code you can open it up (`.rust2ptx/kernel.ptx`) and see what's going on.

## Pitfalls

Now that you can compile and run Rust code on your GPU, you should be aware that LLVM's PTX backend
is not really all that mature at this point, and there are many pitfalls to doing this. Here are
some of the ones that I ran into.

First, this whole process likes to generate invalid PTX files, and CUDA typically gives no
indication what went wrong - just an `INVALID_PTX` error at runtime. Indexing into a slice in the
kernel code produces this error, for example. I thought it might be because of an unresolved
reference to some code used in handling panics, but it happened for me even when I used
`get_unchecked`. I was kind of bummed about this, since I'd hoped that I could just convert the raw
pointers into a slice at the top of the kernel and get back my nice Rust memory-safety, but no such
luck. It would be nice if there was some way to panic on the GPU (even if it only terminated the
kernel somehow) instead of generating an invalid PTX file. Relatedly, indexing into a fixed-size
array also produced this error, but in that case using `get_unchecked` did work.

I also found a couple even-stranger cases which produce `INVALID_PTX` errors. You can't use the
`for x in 0..y` loop at all and instead must use a while loop, manually incrementing a counter.
It's easy to forget the increment, creating an infinite loop. Windows will automatically kill any
kernel that runs for more than a few seconds on the primary display GPU, which helpfully saves you
from misbehaving kernels bringing down the entire system but limits how much computing time you can
use at once. Additionally, implementing any of the `core::ops` traits like Add or Mul produces
`INVALID_PTX` errors for some reason. That's especially annoying when working with Vectors, where
operator-overloading is natural. Another way to trigger `INVALID_PTX` errors is to
`#[derive(Debug)]` for any struct in the kernel code, though deriving `Clone` appears to work just
fine.

Also, for some reason Xargo insists that every crate must have the target-specification JSON file,
which makes it somewhat annoying to use any third-party crate even if they do support `#![no_std]`.
Accel generates it for you in the `#[build_path]` directory, but you'll need to add your own to any
crate that your kernel depends on.

On that note - everything callable by the kernel must be `#![no_std]`-compatible. This is a problem
because a lot of core math routines - including basic stuff like `powf` and `sin/cos` require std
and are not directly available in core. Since you have to use Nightly anyway, though, you can use
many of them anyway by adding `#![feature(core_intrinsics)]` to your lib.rs file and then calling
the unsafe intrinsics in `core::intrinsics`. Bizarrely, I ran into linker errors with some of the
functions - notably the trigonometry functions like sin and cos - when I did this, although others
worked fine. Ultimately, I ended up copying a pure-Rust implementation of these functions from the
[mish crate](https://github.com/shingtaklam1324/mish). It gets the job done, but it would be better
if rustc could emit the `sin/cos` instructions so that these functions could be
hardware-accelerated.

Additionally, there are a lot of things that CUDA programmers are used to which are just not
accessible in rust. There is no way to access any memory space but global memory - local, shared,
texture and constant memory are all unavailable. Furthermore, Accel does not yet provide anything
beyond the basics - there are no streams and no asynchronous memory transfers.

## Conclusion

Although it's true that GPU-compatible Rust code is a lot more similar to C than I'd like, there are
some aspects that make it worth the hassle.

Rust-on-the-GPU still provides a lot of the conveniences of regular Rust. Tuples make for an easy
way to return multiple values. Enums and Structs all work as expected, including pattern-matching,
destructuring and Option (frankly, Option alone is worth all of the trouble necessary to use Rust).

I hope somebody out there finds this useful - this is the document that I wish that I'd had when I
started this crazy project. With that said, though, all of this could benefit greatly from
additional developer attention, from Accel all the way down to rustc and the LLVM PTX backend. It's
my hope that this post can raise some interest and awareness of some of the ways that Rust GPGPU
support is not yet awesome. Maybe we'll see some improvements in this area in the future!