+++
date = "2019-01-22T16:00:00-06:00"
title = "Writing a GPU-Accelerated Path Tracer in Rust - Part 2.5"
tags = ["Rust", "GPGPU", "Raytracer", "Pathtracer"]
categories = ["code"]
author = "Brook Heisler"
draft = true
+++

## Reflection and Refraction

Last time I said that I would talk about making the path tracer faster, but I realized that I haven't covered reflection or refraction in path tracing yet. For the most part, they're both largely the same as in the previous raytracing articles, so I won't re-tread old ground in too much detail. Instead I'll cover some of the challenges that I ran into implementing them in my path tracer, and the next full post will cover making it go fast.

The basic case of total reflection is pretty easy to handle in this system. I just copied the reflection-ray generating code from my old raytracer and plugged it in. Unfortunately, partial reflection and refraction both require some more work.

See, the iterative path-tracing loop I created in the last post assumes that it's only ever tracing one ray at a time. This assumption doesn't work with refraction, though, which requires tracing both a reflection ray and a transmission ray, each containing part of the power of the original ray. Likewise, for partial reflection we need to generate one scattered ray and one reflected ray, each with part of the power.

In the old CPU-based raytracer, we could use recursion to make that work, but as discussed in the last post, recursion seems to break my kernel for some reason, even though modern GPUs officially support it. So, that's out and we need another way to trace multiple rays simultaneously.

The normal trick when converting these sorts of recursive algorithms to be iterative is to keep some extra space to store the data that would otherwise be stored in the call stack (think of how you might use a Stack data structure to perform an iterative depth-first-search of a tree, for example). In this case, our options are somewhat limited. We don't have a heap on the GPU, so we can't use any sort of dynamic memory allocation. Instead, everything must be pre-allocated by the CPU code and provided to the kernel.

So, we'll create a fixed-size scratch-space in GPU memory for each thread to use, and we can store our extra rays there. Then we merely have to loop over the scratch space and trace/update each ray there, just as we already trace and update a single ray.