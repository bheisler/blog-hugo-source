+++
date = "2019-01-22T16:00:00-06:00"
title = "Running Rust on the GPU with Accel"
tags = ["Rust", "GPGPU", "Accel]
categories = ["code"]
author = "Brook Heisler"
draft = true
+++

## Intro
- Some background on Accel and this project

## Installing and configuring everything for Accel
- Need CUDA libs installed
- Export CUDA_LIBS_DIR
- Need Xargo installed (and mention the +nightly thing)
- Installing and/or compiling LLVM tools

## Basic Example
- Show the add example from Accel

## Structure Ideas
- Accel can compile in external crates, so I think it makes sense to put
  all of your actual logic in a kernel crate and make your #[kernel] function just a thin wrapper around that. This also allows you to share code (eg. structure definitions) between your kernel and your host code, or even have the host code depend on the kernel crate as well and call it directly on the host without launching it as a kernel.

## Pitfalls
- INVALID_PTX error on indexing into a slice. That's annoying. I thought it might be the panic on out-of-bounds access code, but if I call get_unchecked it fails as well.
- You need to copy the target specification file into all crates used by the kernel for some reason.
- Everything callable by the kernel needs to be no_std, which is really annoying because a lot of core routines like powf are 
- INVALID_PTX errors happen in very strange situations. For example, this code gives an INVALID_PTX error:

```
#[derive(Clone, Copy)]
pub struct Vector3 {
    pub x: f64,
    pub y: f64,
    pub z: f64,
}
impl Add for Vector3 {
    type Output = Vector3;

    fn add(self, other: Vector3) -> Vector3 {
        Vector3 {
            x: self.x + other.x,
            y: self.y + other.y,
            z: self.z + other.z,
        }
    }
}
```

But this code doesn't:

```
#[derive(Clone, Copy)]
pub struct Vector3 {
    pub x: f64,
    pub y: f64,
    pub z: f64,
}
impl Vector3 {
    pub fn add(self, other: Vector3) -> Vector3 {
        Vector3 {
            x: self.x + other.x,
            y: self.y + other.y,
            z: self.z + other.z,
        }
    }
}
```