+++
date = "2018-08-08T20:00:00-06:00"
description = ""
title = "The State of GPGPU in Rust"
tags = ["Rust", "GPGPU"]
categories = ["code"]
+++

At work a few months ago, we started experimenting with GPU-acceleration. My boss asked if I was
interested. I didn't know anything about programming GPUs, so of course I said "Heck yes, I'm
interested!". I needed to learn about GPUs in a hurry, and that led to my [GPU Path Tracer
series](/post/writing-gpu-accelerated-path-tracer-part-1.md). That was a lot of fun, but it showed
me that CUDA support in Rust is pretty poor. If our experiments ever turn into an actual product, I
would have to recommend we write the GPU code in C.

To spare myself and others that dreadful fate, I decided to work towards making Rust's GPGPU story
as good as C's. The first step was to survey the landscape to see what's out there.

## OpenCL

I started by looking at OpenCL crates. I found two -
[rust-opencl](https://github.com/luqmana/rust-opencl) and [ocl](https://crates.io/crates/ocl).
`rust-opencl` is abandoned, so I'll focus on `ocl`.

I'm not very familiar with OpenCL, but `ocl` looks pretty solid to me. It provides Rustic
abstractions over the OpenCL C API, but allows the programmer to drop down to the lower level if
needed. OpenCL in Rust is already as good as it is in C. OpenCL works on AMD GPUs as well as
NVIDIA ones, which is a nice bonus.

I don't much like OpenCL, though. OpenCL kernels are written in OpenCL C, and the source code is
passed to the GPU driver for compilation at runtime. I want to avoid writing C. Further, the
runtime compilation model and change of language means that we lose all of the nice compile-time
safety checks that Rust provides.

## CUDA

Despite being NVIDIA-only, CUDA seems to be more widely used than OpenCL, and it's not hard to see
why. It provides an easy, single-source approach to GPGPU - you write C or C++ and mark GPU code
with special annotations. Compile the code with a compiler-wrapper called `nvcc`, and then you can
launch kernels almost as easily as calling a function. The library APIs are well-designed and
intuitive for C programmers. I used CUDA for my path tracer series. CUDA support in Rust was pretty
rough, and it's hasn't gotten better.

CUDA in Rust should be just as smooth as it is in C. `rustc` already supports LLVM's NVPTX
backend. You can write Rust code, mark it with some procedural macros and execute it on the GPU.
You can share structure definitions and functions between the CPU and the GPU, the compiler
provides all of its usual compile-time checks, and it all works smoothly, right?

Well, no. The NVPTX backend is right at the bottom of [Tier 3 support](https://forge.rust-lang.org/platform-support.html)
with a lot of asterisks. To compile to PTX, you have to use a specific nightly build (2018-04-10)
and you have to use Xargo to cross-compile the `core` library. You have to install a bunch of extra
LLVM tools to link together different crates (which may involve compiling them from source). Once
you fight through all of that, `rustc` frequently produces an invalid PTX file or just crashes and
you have to guess why. It's... not great.

[accel](https://github.com/rust-accel) is still best-in-class here, but that's not saying much.
They've forked the Rust compiler to improve PTX support and made a tool to install their custom
compiler into your `rustup` toolchains. Unfortunately, that tool only works on Linux. The
documentation is poor, and even getting it to work on Linux requires digging into the source code
to decipher mysterious error messages.

There are Rust bindings for many CUDA libraries like [CuBLAS](https://crates.io/crates/cublas), but
these are also abandoned.

CUDA in Rust needs a lot of work to catch up to CUDA in C.

## Higher-Level Libraries

There are a number of libraries seeking to provide higher-level interfaces to the GPU.

The oldest is [Collenchyma](https://github.com/autumnai/collenchyma), which came out of Leaf AI and
focuses on neural networks. It was completely abandoned along with Leaf. A fork called
[Parenchyma](https://github.com/jonysy/parenchyma) was created, which changed a lot of
Collenchyma's API and claims to be under active development. There hasn't been a Git commit in six
months. It's probably abandoned as well, and remaining users are unable to compile it on the latest
nightly compiler builds.

The other big one is [arrayfire-rust](https://github.com/arrayfire/arrayfire-rust), which is a Rust
binding to ArrayFire. This is attached to ArrayFire LLC, so it has some corporate backing and
probably won't be totally abandoned. Unlike Parenchyma, it has some activity in the last few
months. ArrayFire provides the ability to create and fill arrays of values and then apply pre-baked
operations to them. If you want lower-level control to get that last bit of performance, or if your
problem doesn't fit their model, then I think you're out of luck. I'm skeptical of claims that it's
portable across OpenCL, CUDA and CPUs. The performance characteristics of CPUs are so different
from those of GPUs that it will be difficult to get optimal performance on both.

ArrayFire in Rust is at least as good as ArrayFire in C, but that's about all I can say. There is
nothing similar to [Thrust](https://developer.NVIDIA.com/thrust) or
[OpenACC](https://developer.NVIDIA.com/openacc) yet.

## Other Rust GPGPU Projects

[Vulkano](https://github.com/vulkano-rs/vulkano) is a Rust interface to the Vulkan graphics API. It
supports compute shaders as well. All of my concerns with OpenCL apply here as well - it uses a
special C-like language (similar to the one OpenCL uses) for the shaders rather than plain Rust.
The surrounding API is quite verbose as well. I think Vulkan is primarily focused on graphics, and
compute-shaders are provided as an extension to that.

I'd also like to mention [rlsl](https://github.com/MaikKlein/rlsl) - Rust-Like Shading Language.
This compiles a subset of Rust to Vulkan SPIR-V. It's an interesting project, but the README warns
that it is not production-ready and does not accept contributions yet. This too is focused on
writing shaders for graphics rather than general-purpose computation.

## Conclusion

If you like OpenCL, Vulkan or ArrayFire, all of them have excellent Rust bindings. On the other
hand, CUDA in Rust is simply not ready for use in production. Rust has no alternative for many
other GPGPU tools that C/C++ programmers have, like Thrust or OpenACC.

GPGPU is an important use-case for a low-level, high-performance language like Rust. It's relevant
to a number of fields, including machine learning, cryptography, cryptocurrency, image-processing,
physical simulations, and scientific computing.

I want to work to improve this situation. I think the CUDA model of writing host and device code in
the same language is valuable, so that's what I'll start with. This will involve working with the
Rust compiler team and contributing improvements to `rustc`, maybe even LLVM. Aside from some bug
reports I've never done that before, and it would help to have a mentor. If you'd be willing to
answer questions like "what would have to happen before NVPTX could be a Tier 2 backend" or "how do
I get this build system to work on Windows", please send me an email or [post a comment](https://github.com/bheisler/blog-hugo-source/issues/1).

[Comments](https://github.com/bheisler/blog-hugo-source/issues/1)