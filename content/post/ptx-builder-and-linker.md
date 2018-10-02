+++
date = "2018-10-01T19:00:00-06:00"
description = ""
title = "Porting My CUDA Path Tracer to ptx-builder/linker"
tags = ["Rust", "GPGPU"]
categories = ["code"]
+++

A bunch of stuff has happened since I published my post on [The State of GPGPU in Rust](/post/state-of-gpgpu-in-rust.md).
Most importantly, [Denys Zariaiev (@denzp)](https://github.com/denzp) released his work on a 
[custom linker](https://github.com/denzp/rust-ptx-linker) for Rust CUDA kernels, and a 
[build.rs helper crate](https://github.com/denzp/rust-ptx-builder) to make it easier to use.

These two crates eliminate many of the problems I referred to in my previous post. The linker
solves most of the "invalid PTX file" problems, while the ptx-builder crate does all of the magic
that Accel was doing behind the scenes. In addition, the 
[compiler bug](https://github.com/rust-lang/rust/issues/38824) which prevented us from using current
Rust builds has been resolved (again, thanks to @denzp. All glory to @denzp).

I ported my [GPU Path Tracer](/post/writing-gpu-accelerated-path-tracer-part-1.md) code to this new
system to check it out. I'll be clear - there are still enough pitfalls and limitations and 
[compiler bugs](https://github.com/rust-lang/rust/issues/54115) that I would not yet recommend using
Rust for production CUDA work. I think we now have a stable base to build on, though.

This post serves as a write-up of how I removed Accel from my path tracer and the problems I
encountered along the way. It could also serve as a tutorial for the brave early-adopters out there
who want to try something similar.


## Build Script

I started by pasting the example `build.rs` script from the 
[ptx-builder project](https://github.com/denzp/rust-ptx-builder). I missed the bit where
it says the build script is for the host-side (CPU) crate, not the kernel crate, but after I got 
that sorted out it worked without modification.

{{< gist bheisler 5b61f3cc7dfb6d28e174a5c52caa0b81 >}}

I haven't worked with `build.rs` files before, so I think it's useful to break down
what this script does. Much of the code at the top of the file is trivial, so I'll start with
this:

```rust
let status = Builder::new("kernel")?.build()?;
```

This builds the `kernel` crate and links it and its dependencies into a PTX module. `kernel` in this
case is a relative directory name. Then, if the build was successful...

```rust
// Provide the PTX Assembly location via env variable
println!(
    "cargo:rustc-env=KERNEL_PTX_PATH={}",
    output.get_assembly_path().to_str().unwrap()
);

// Observe changes in kernel sources
for path in output.source_files()? {
    println!("cargo:rerun-if-changed={}", path.to_str().unwrap());
}
```

The build script reports the path to the PTX file to Cargo as an environment variable (so that we
can embed it into our executable later using `include_str!(env!("KERNEL_PTX_PATH")))`, and informs
Cargo that the host crate needs to be recompiled if any of the kernel source files change. This is
really slick - props both to @denzp and the Cargo team for making this work so smoothly. If you had
multiple kernel modules, you could call the builder multiple times and expose them as separate
environment variables as well.

## Converting the Kernel

With Accel, I had a wrapper function tagged with the Accel procedural-macro attribute which was
responsible for calling the function in my kernel crate to do the rendering work. I moved that into
the kernel crate itself:

{{< gist bheisler b1b122814ba4829e84edccb7fad0ee5c >}}

This is the only part of my kernel that accesses the NVPTX builtins, so I added the `cfg` attribute
to remove this function when not compiling for CUDA. That way I could still call the rest of the
kernel on the CPU for testing and easier debugging when needed. After that, there's the
`#[no_mangle] pub unsafe extern "ptx-kernel" fn` dance necessary to expose this function as a
kernel entry point, and the actual code. Using the "ptx-kernel" as the ABI tag means I needed to
add `#![feature(abi_ptx)]` to the crate and run with a nightly build. If you're following along on
Windows, you'll also need to use the `windows-gnu` nightly, as the PTX linker currently doesn't
work with the `windows-msvc` builds.

Accel has its own crate that provides wrappers for the `block_idx`/etc. functions, but I followed
@denzp's guide and used the [`nvptx_builtins` crate](https://crates.io/crates/nvptx-builtins).
`nvptx_builtins` is super bare-bones, but that's probably what you want here - the magic CUDA
functions are very limited in scope so you don't really need anything complex.

With that, converting the kernel was done. Remarkably easy, in fact.

## Data Transfer

Next, I needed a way to transfer data to and from the GPU. Accel handles this with a special `UVec`
type, which is essentially a fixed-size `Vec` in [Unified
Memory](https://devblogs.nvidia.com/unified-memory-cuda-beginners/), meaning that it can be
transparently read or written by both CPU and GPU code without an explicit transfer step. This is
useful, but my memory access patterns were pretty simple so I just did the copying explicitly.

This brings me to another point I'd like to make - we need a better higher-level wrapper around
CUDA. Accel's is pretty decent but is tied up with that project. I'm using
[japaric/cuda](https://github.com/japaric/cuda) here because that's what @denzp used in his
examples, but it's not ready for production use. I shouldn't have to write my own struct to safely
handle allocating memory on the GPU, there are a bunch of simple structs that should implement
Clone but don't, several parameters to important functions should be taken by reference, and
so on. It doesn't appear to be maintained any longer, and was never published to Crates.io.

In any case, I wrote a simple `DeviceBuffer` struct to allocate device memory, free it on Drop, and
copy data to or from the device. Then I updated all of my code to use that structure instead of
`UVec`.

## CUDA Context

At this point, I had the code compiling (although I had commented out the code to launch the
kernel). It failed as soon as it tried to allocate device memory, though, because I needed to
initialize the CUDA context.

Initializing the driver itself is easy:

```::cuda::driver::initialize().expect("Unable to initialize CUDA");```

Then I needed to create and manage a CUDA context. This was more difficult than it needed to be, but
that's really my fault for my poor design when building the path tracer. The problem is that
the CUDA context structure needs to be used to load PTX modules and launch kernels, so it had to be
accessible in the launch function, several calls down from main.

The natural way to handle this is to have a single `PathTracer` struct which contains all of the
important shared state for the path tracer and have `main` instantiate and use that. I should have
done that to start with, but I didn't and I didn't feel like refactoring. Instead, I just left
everything as a local variable in `main`, and I didn't want to thread the reference to the context
down to where it would be needed, so I cheated and used `lazy_static!` to make it global. Forgive
me, programming gods, for I have sinned.

{{< gist bheisler 468ba641f3816b0cc745b974f384ed26 >}}

I did the same for the CUDA module, which holds the compiled PTX code. Notice here 
that we're using the `env!` macro to get the path to the compiled kernel from the environment 
variable set by the build script. We then use `include_str!` to embed the kernel code into our
executable. It's a bit unfortunate that we have to copy it to a heap-allocated CString before
handing it off to CUDA - it would be nice to have an `include_cstr!` to include the kernel as a
null-terminated string - but it's not a big deal. Likewise how we have to explicitly convert the 
rust `&str` to a `CStr` on each call to the `kernel` function, even though the parameter is almost 
certainly a constant.

I would like to explore the idea of building some macros (perhaps procedural macros) to help with
this. One approach would be to have an `include_cstr!` macro. Another option would be for the build
script to assemble the (text-based) PTX file using `ptxas`, and then embed the resulting binary
using `include_bytes!`. In either case, it would also be great to have a `cstr!` macro for creating
CStr literals.

{{< gist bheisler f8bde9a1a5ec152952e2838f0b95fa03 >}}

## Launching the Kernel

With all that set up, now I could launch the actual kernel:

{{< gist bheisler 9e37fffc987d6b6e128c78d1ee082f27 >}}

It's worth noting here that the launch function blocks until the kernel is complete. Normally,
CUDA kernel launches are asynchronous - the launch returns almost immediately to allow the CPU to
queue up more work or perform memory transfers to and from the GPU while it's working. This is
another limitation of this particular wrapper library. I've been thinking about using
Rust's futures libraries to model this asynchronous behavior, but for now it would be nice if
we could just have access to the same API that C programmers use.

Also note the manual construction of the argument array to pass to the kernel. I think a lot of
this verbosity can be eliminated with some macros. I should probably write those macros. Anyway, 
with this done, the path tracer port was complete.

## Conclusions

For me, the biggest take-away from this is that we need a well-designed, well-documented Rust wrapper
around the CUDA driver and runtime APIs. The kernel side of things is basic but good enough for
initial use (modulo compiler bugs) but the facilities for working with device memory and launching
kernels are limited and awkward. Down the road, we'll need to tackle things like shared memory
somehow, and we'll probably want to start building higher-level tools for kernels as well.

Still, now that we have the PTX linker and build script tools, it's possible to reliably build CUDA
kernels in Rust and execute them without relying on specific compiler versions. It's just more work
than it really ought to be. That's a major step forward towards making GPGPU in Rust as good as it
is in C.