+++
date = "2018-12-01T15:00:00-06:00"
title = "Announcing RustaCUDA v0.1.0"
description = ""
tags = ["Rust", "CUDA", "RustaCUDA", "GPGPU"]
categories = ["code"]
+++

In [my post on GPGPU in Rust](/post/state-of-gpgpu-in-rust/), I declared that I intended to work
on improving the state of CUDA support in Rust. Since then, I've been mostly radio-silent. I'm
pleased to announce that I _have_ actually been working on something, and I've finally published
that something.

## RustaCUDA

[RustaCUDA](https://github.com/bheisler/RustaCUDA) is a new wrapper crate for the CUDA driver API.
It allows the programmer to allocate and free GPU memory, copy data to and from the GPU, load CUDA
modules and launch kernels, all with a mostly-safe, programmer-friendly, Rust-y interface. It can
load and launch kernels written in any CUDA-compatible language, not just Rust.

I've put a lot of effort into the documentation as well as the code. I hope that RustaCUDA can help
introduce more Rust programmers to the fascinating world of GPGPU programming.

## Example

I'll walk through a simple example to demonstrate. We'll write a kernel in CUDA C which takes two
buffers of floating-point numbers as input, adds each pair of elements, and writes the sum into a
third buffer of floats. Then in Rust, we'll allocate device memory to hold the buffers, fill them
with numbers, launch the kernel to compute the sums, copy the results back to the CPU and print
them out.

Before we start, you will need to download and install [the CUDA
toolkit](https://developer.nvidia.com/cuda-downloads), version 8.0 or newer. You will also need a
CUDA-compatible GPU. Finally, set an environment variable pointing to where you installed the CUDA
libraries. For my MINGW terminal, that would be:

```
export CUDA_LIBRARY_PATH="C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v9.1\lib\x64" 
```

First, we'll create a Rust project:

```
cargo init --bin rustacuda_example
cd rustacuda_example
```

Edit your `Cargo.toml` file to add:

```
[dependencies]
rustacuda = "0.1"
rustacuda_derive = "0.1"
rustacuda_core = "0.1"
```

Before we move on to the Rust code, however, we need a kernel to run. Copy the following code into
a file called `add.cu`:

{{< gist bheisler 1d8c919692d708475973fa646c6fbb12 >}}

Since this isn't really about CUDA C, I won't go into too much detail on this. In short, this
declares a kernel that takes two float arrays (`x` and `y`), iterates over the arrays, adds each
pair of elements and writes the sums into `out`. CUDA works by executing the same function on many
threads, so all of the `blockIdx.x` and similar is there so that each thread will take a different
element of the array.

Compile the kernel file to a PTX file:

```
nvcc add.cu --ptx -o add.ptx --gpu-architecture=compute_32
```

Now paste the following code into `src/main.rs` (I'll explain it below):

{{< gist bheisler c3778c134fa79ec1c941daff20afdcba >}}

Let's break this down step by step.

First, we need to initialize CUDA and create a Context:

```
// Initialize the CUDA API
rustacuda::init(CudaFlags::empty())?;

// Get the first device
let device = Device::get_device(0)?;

// Create a context associated to this device
let context = Context::create_and_push(
    ContextFlags::MAP_HOST | ContextFlags::SCHED_AUTO, device)?;
```

A Device is just a handle to a CUDA GPU, and for the purposes of this example we don't really care
what GPU it is as long as it supports CUDA. Then we create the context. Contexts in CUDA are sort
of similar to a process on the CPU - it holds all of the functions we load, all of the
configuration settings and all of the device memory allocations. Like with processes, a Context
also has it's own memory space - that is, pointers from one context won't work in another. A
context is tied to a device, and there should be exactly one context per device (you can have more
than one, but changing contexts for a device is slow). The context flags aren't important to this
example, but they're good defaults anyway.

Next up we load a Module containing our compiled PTX code:

```
// Load the module containing the function we want to call
let module_data = CString::new(include_str!("../add.ptx"))?;
let module = Module::load_from_string(&module_data)?;
```

Here, we use `include_str!` to include the compiled PTX file directly into our binary. Then we
convert it to a `CString` and ask CUDA to load a module from that. A Module is sort of like a
dynamically-linked library - it's loaded at runtime and exports functions that we can call.

Then we create a Stream:

```
// Create a stream to submit work to
let stream = Stream::new(StreamFlags::NON_BLOCKING, None)?;
```

Once again, the exact stream flags are not important for this example, but they're a good default.
To continue with the CPU analogies, a Stream is sort of like a thread, or perhaps a single-threaded
executor. Asynchronous operations in CUDA are submitted to a Stream, which processes them in the
order they were submitted. Operations submitted to one stream can interleave or overlap with
operations submitted to a different stream, just like running tasks in multiple CPU threads.

```
// Allocate space on the device and copy numbers to it.
let mut x = DeviceBuffer::from_slice(&[10.0f32, 20.0, 30.0, 40.0])?;
let mut y = DeviceBuffer::from_slice(&[1.0f32, 2.0, 3.0, 4.0])?;
let mut result = DeviceBuffer::from_slice(&[0.0f32, 0.0, 0.0, 0.0])?;
```

Here we allocate the three buffers that our kernel uses. `DeviceBuffer<T>` is an owning handle to an
allocation of GPU memory. You can sort of think of it like a `Vec<T>`, except much more restricted.
You can't resize a `DeviceBuffer` or write directly to it, but instead you have to copy data to and
from CPU memory explicitly. In this case, I've used the `from_slice` function to allocate a buffer
and copy data to it in one step.

Now that we've done all of the setup work, we can launch the kernel:

```
// Launching kernels is unsafe since Rust can't enforce safety - think of kernel launches
// as a foreign-function call. In this case, it is - this kernel is written in CUDA C.
unsafe {
    // Launch the `add` function with one block containing four threads on the stream.
    launch!(module.add<<<1, 4, 0, stream>>>(
        x.as_device_ptr(),
        y.as_device_ptr(),
        result.as_device_ptr(),
        result.len()
    ))?;
}

// The kernel launch is asynchronous, so we wait for the kernel to finish executing
stream.synchronize()?;
```

The `launch!` macro looks up the `add` function in our module and launches it with the given
parameters. If you're familiar with CUDA already, the syntax should be pretty familiar. If not,
the `<<<...>>>` section describes how the kernel should be launched. I've already mentioned how
CUDA runs a function on many threads simultaneously. These threads are grouped into blocks, which
are themselves grouped into grids. Blocks and Grids can be up to three dimensions, which is helpful
when operating on multi-dimensional arrays (for example, using a 2D block to render part of a 2D
image). In this case, we only need one dimension, with one block of four threads. 

After launching the kernel, we have to block the CPU thread to wait for the kernel to complete. If
we didn't, we might see incomplete values when we copy the results back to the CPU. Speaking of
which:

```
// Copy the result back to the host
let mut result_host = [0.0f32, 0.0, 0.0, 0.0];
result.copy_to(&mut result_host)?;

println!("Sum is {:?}", result_host);
```

If everything worked, you should be able to run this program:

```
$ cargo run
   Compiling rustacuda_example v0.1.0
    Finished dev [unoptimized + debuginfo] target(s) in 1.02s
     Running `target\debug\rustacuda_example.exe`
Sum is [11.0, 22.0, 33.0, 44.0]
```

Success! For those who would prefer to write kernels in Rust, I encourage you to check out
[denzp/rust-ptx-builder](https://github.com/denzp/rust-ptx-builder), which is a build-script helper
for easily compiling your kernel crate to PTX.

## Next Steps

Right now, RustaCUDA only provides the bare minimum of functionality necessary to load and launch
basic kernels. I hope that it will eventually expose all of the CUDA Driver API's functionality.

To that end, I would like to invite you to try RustaCUDA out and raise issues for problems you
find. I've ported my path tracer to use RustaCUDA successfully, but more testing would be great. I
also hope to build up a larger community of contributors to this crate. No need to worry if you're
new to CUDA, either - there are several [beginner-friendly
issues](https://github.com/bheisler/RustaCUDA/issues?q=is%3Aissue+is%3Aopen+label%3ABeginner)
available.

As for me, I plan to spend some time working on
[Criterion.rs](https://github.com/japaric/criterion.rs), which I have badly neglected lately. Thank
you to all Criterion.rs users and contributors for their patience while I've been busy working on
this CUDA thing.