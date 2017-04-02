+++
#TODO: fix date
date = "2017-04-02T00:00:00-06:00"
description = ""
title = "Calling Rust From Python"
#TODO: Add image
images = [
    "https://bheisler.github.io/static/rendered-by-python.png"
]
+++

# Introduction

Hello! This is a detailed example of exposing Rust code to other languages (in
this case, Python). Most articles I've seen that cover this topic uses really
trivial example functions, skipping over a lot of the complexity. Even the better
ones out there typically don't have a pre-existing, reasonably complex program
to work with. I'm going to start with trivial functions and build my way up to
being able to define a scene for my [raytracer](https://github.com/bheisler/raytracer)
in Python using a series of calls to Rust, then render it and return the
resulting image data back to Python. If you want to know more about the raytracer,
I wrote a series of posts on it [here](/post/writing-raytracer-in-rust-part-1/),
but it won't be necessary; I'll explain parts of the raytracer here as we need
them. Hopefully this will give a more complete picture of how to incorporate
complex Rust code into Python.

I've never written any sort of Python/C interop before, so this should be another
learning experience all around. I'm going to arbitrarily choose
[CFFI](https://cffi.readthedocs.io/en/latest/) as the Python interop library.
It's portable across interpreters and seems nicer to use than [ctypes](https://docs.python.org/2/library/ctypes.html).
I expect the main concepts will be broadly applicable to other libraries (and
other languages such as Ruby). Let get started!

## Calling Functions

The first thing to do is to define a Rust function we want to call from Python.

{{< gist bheisler effc8c457c9d85d1e318be52e1b8c98d >}}

We're actually defining a function for Rust's C foreign-function interface. The
basic idea here is that we write a wrapper in Python that knows how to call
C functions, and a wrapper in Rust that exposes C functions and translates them
to regular function calls in Rust. It's sort of like we're calling from Python
into C into Rust. The `no_mangle` attribute and `extern "C"` above instruct rustc
not to change the name of the function (otherwise CFFI wouldn't be able to
find it later) and to emit a function that can be called as if it were written
in C. We'll need both for all functions that we want to expose to C.

Now we need to instruct Cargo to build this library as a dynamic library
("dylib" in Cargo terms). I'm writing this on a Windows PC, so Cargo
produces a `raytracer_ffi.dll` file. I tested it on Linux as well and it created
`libraytracer_ffi.so`.

{{< gist bheisler 06c25b67a35bfd8f5b38781256558230 >}}

Then we need some Python code to load and call this shared library:

{{< gist bheisler ec798db12cd69153a6330e67eb6d3dac >}}

Let's break this down a bit. First we import the `cffi` module and create an
FFI object. Then we call `cdef` and pass it some text - this text is a C function
signature matching the `double` function in Rust. CFFI parses this function
signature in order to determine how to call the function. We'll need to do this
for all of the functions and structs we want to expose to Python. Then we open
the DLL file with `dlopen`. Finally, we call the `double` function as if it were
a regular Python function and print the result.

And now we should be able to call `double` from Python:

    $ python.exe test.py
    18

Side note: I wasn't able to get this working with PyPy on 64-bit Windows. I
didn't find out why, but I assume it has something to do with how PyPy only
provides 32-bit binaries. PyPy worked fine for me on Linux, but I had to use
64-bit CPython on Windows.

## Passing Structures

Now, if I'm going to be able to define a scene in Python, I'll need to be able
to call functions and pass in structs as arguments. I'll keep working with this
toy program a bit longer, but instead of simply doubling an integer, let's try
and get it to calculate the length of a vector using `vector::Vector3::length`.

First, I'll need to tell rustc that Vector3 should be laid out like a C struct.

{{< gist bheisler 23de3e8f86143ceea2240b2a283b8f91 >}}

It appears that CFFI doesn't have any way to call functions with stack-allocated
structures. Using the stack for small, copyable structures like Vector3 is
pretty common in Rust, but I guess it isn't in C? So instead, our Rust function
will have to accept a pointer to a Vector3.

{{< gist bheisler f02545b55a01f5602f9aa8802c970847 >}}

Here we define an extern function which accepts a raw pointer to a Vector3.
Dereferencing raw pointers is unsafe, so we use an unsafe block to convert the
raw pointer to a Rust reference. Finally, we call `length()` and return the value.

{{< gist bheisler d7c3c411f6826303a8a09868821b6829 >}}

Back in Python-land, we define a structure type matching Vector3 and the
signature of the length function. Now we need to allocate a new vector_t object,
which is done with the `ffi.new()` function. We need to pay attention to
ownership here - the memory for the vector_t is allocated by Python and it will
have to be freed by Python. In this case, it will be freed when the vector object
gets garbage collected so we don't need to worry about it, but we'll need to
be more careful about ownership later.

    $ python.exe test.py
    1.73205080757

## Returning References Back To Python

Now we'll start the process of building our actual FFI code. We'll start with the
Scene structure. I don't especially want to expose all the complexity of the
Scene structure to Python, so instead we'll use another C idiom and return an
opaque pointer.

{{< gist bheisler 9a552f490d320410b28ab5e6c065ee9f >}}

Notice that we use `Box::new` to heap-allocate the structure, and `Box::into_raw`
to convert it into a raw pointer to return. The corresponding Python code is:

{{< gist bheisler fcdb3bc11c85147172e1a6ec42f224d0 >}}

I'm not actually sure `void*` is the right way to go here, but I don't know any
other way to do opaque pointers in this situation. If you know more about this,
let me know. CFFI seems to understand `uint32_t` all on its own, and presumably
will call the Rust function with the appropriate integer width.

    $ python.exe raytracer.py
    From Rust: Scene { width: 800, height: 600, fov: 45, elements: [],
        lights: [], shadow_bias: 0.0000000000001, max_recursion_depth: 10 }
    From Python: <cdata 'void*' 0x000000000155B260>

Sharp readers might have noticed that we're leaking Scene objects - we're
allocating some memory on the heap for the boxed Scene and never freeing it.
For this trivial example, it doesn't matter much because it will be cleaned
up when the process terminates, but it is rather inelegant, so let's fix that.

## Disposing Of Allocated Objects

This goes back to the brief discussion of ownership earlier. Previously,
Python owned the allocated Vector3 object, so we could trust that it would be
safely freed when it was garbage-collected. Now, we have an object allocated by
Rust, but owned by a pointer in Python. Python doesn't know how to deallocate
an object owned by Rust, so we'll have to return ownership of the pointer to
Rust and allow Rust to free the memory.

{{< gist bheisler 2f98fb5590e4dcd895773b1dd39a100d >}}

Freeing the memory is actually quite simple - we use `Box::from_raw` to convert
the raw pointer back into a box, and then just let it fall out of scope. Rust
will automatically clean everything up for us.

{{< gist bheisler 51656ea2be9b8d0c2e7ba2c6ba77bfe4 >}}

Right now, there's nothing to stop us from freeing the scene more than once,
or continuing to use that pointer after the scene has been freed. There's nothing
we can do about that from the Rust side, but in Python we can at least build a
safe wrapper to work with.

{{< gist bheisler ba18f7b5c73c66ad9d1924e80881fc9e >}}

Here, we define a Python class to represent our Scene. It defines the `__enter__`
and `__exit__` methods necessary to act as a [Context Manager](https://www.python.org/dev/peps/pep-0343/),
which allows us to use it with the `with` statement at the end. Running this
file confirms that the scene object is being freed:

    $ python.exe raytracer.py
    Freeing the scene

## Enums

Before we begin constructing our scene in Python, however, there's one more bit
of complexity to tackle first. Every object in this raytracer contains a Material
structure to define what color the surface is, whether it's reflective or
transparent, etc. This is defined in Rust using some enums and a struct:

{{< gist bheisler 5af67a2bc9fb63ad1c77e087d5857c91 >}}

Rust's enums have no equivalent in C, and even if they did that DynamicImage
type certainly doesn't. We'll have to create C-compatible wrappers for these
types that we can expose to Python. I'll focus on the Coloration enum for now,
the SurfaceType enum will work the same way.

We'll start by defining another enum:

{{< gist bheisler 153001fea515624f8eaaf807640c79bb >}}

I know, I just said we can't do enums in C. Instead, we'll define a couple of
functions to create CColoration values on the heap and return opaque pointers
to them like we did with the Scene.

First, the simple case of a solid color:

{{< gist bheisler 37004afc200aa009204031f1443a2ad9 >}}

Then, the more complex case of a path to a texture file.

{{< gist bheisler 8fc77676d46de395b661c89bb0f5384d >}}

Here we take a pointer to a null-terminated character array (a C-style string)
and convert it to a Rust string, which has a length and is encoded in UTF-8.
This conversion could fail, if the C string isn't valid UTF-8. Notice that we
need to be very careful not to panic. We can't just unwrap the result of
converting the CStr to a regular string, because panicking across FFI boundaries
is undefined behavior. Instead, we return a null pointer on all error
conditions. A more serious project would probably want to have more robust error
handling, but this is sufficient for now.

The corresponding Python should be relatively familiar by now:

{{< gist bheisler 02f53a18cc343e57b3a6e9b0c31678a4 >}}

The SurfaceType enum works basically the same way as above, so I'll spare you
the details.

{{< gist bheisler fbfb35e8b010c89e7b40cc5b93b65a2c >}}

All those with's are kind of ugly, but that's the price we pay for safety.
We can verify that everything is being freed as expected:

    $ python.exe raytracer.py
    Freeing surface type
    Freeing surface type
    Freeing surface type
    Freeing coloration
    Freeing coloration
    Freeing coloration
    Freeing coloration
    Freeing coloration

## Constructing the Scene

Finally, we're ready to start constructing the scene. I'll focus on the case of
adding a Sphere to the scene. The code to define other objects is pretty much
the same.

First, we need a new struct to represent Material:

{{< gist bheisler b90e0a5de2bdbc16d0120142bf6b94ba >}}

And a function to add a sphere to a scene:

{{< gist bheisler bede2aa436be20ede3c7c876f2f28488 >}}

Most of this is the now-familiar C foreign-function boilerplate. The
`material.to_rust()` method works pretty much as you'd expect - it
constructs a Material value from a CMaterial value, potentially loading the
texture contained in the `CColoration`. More noteworthy is the way we convert
the scene Box back into a raw pointer at the end of the method. This prevents
Rust from deallocating our scene.

You might reasonably ask why I chose to have one function that creates and adds
the sphere directly to the scene. This does, after all, make it impossible for
me to return a Sphere to Python. The answer is that since I don't really want to
manipulate Spheres in Python, there's not much point in going to all that extra
effort. You can go ahead and do that if you like.

Now that we have all of that, we can call it from Python as before:

{{< gist bheisler 690a6cc77c1e3ba295f5ce45798b6f26 >}}

    $ python.exe raytracer.py
    Sphere { center: Point { x: 0, y: 0, z: -5 }, radius: 1, material:
      Material { coloration: Texture, albedo: 0.18, surface:
      Reflective { reflectivity: 0.7 } } }

## Rendering and Returning the Image To Python

Now that we can define a scene in Python, we need a way to render it and return
the resulting image. We can't just return a byte array, because Python can't
handle stack-allocated objects, and anyway it would overflow the stack. We could
return a pointer/length pair, but then we have to pass it back to Rust to free
it. Instead, we'll follow the C convention and have the caller provide a buffer
to render the image into.

{{< gist bheisler 5c3983559358ef40d4de64d83a44cf61 >}}

After the usual boilerplate, we convert the C-style byte array into a mutable
slice with the `slice::from_raw_parts_mut` function, then wrap that into an
ImageBuffer and pass it to the raytracer for rendering. Slices in Rust don't
own their contents, so we don't need to do anything special to prevent Rust from
trying to free the buffer.

{{< gist bheisler 51eb8b1f5ad6067942d8a1a969842185 >}}

In Python, we need to save the dimensions of the image so that we can allocate
an appropriate buffer. The raytracer uses 4-byte RGBA pixels, so we calculate
the buffer size as 4 * width * height, allocate an appropriate buffer, and
render the image into it. Then we call `ffi.buffer` to wrap it into a convenient
Python object. Finally, we pass that to the Pillow library to be wrapped into
an Image object that we can save out to disk or do further processing on.

[![Rendered By Python](/static/rendered-by-python.png)](http://imgur.com/a/knyif)
Click to see high-resolution image

## Conclusion

Overall, this turned out to be easier than I'd expected. CFFI's user-friendly
interface helped a lot, I think, though the Rust side has a lot of boilerplate.
I expect some macros or something could help with that. I'd like to thank Jake
Goulding and co. for the [Rust FFI Omnibus](http://jakegoulding.com/rust-ffi-omnibus/slice_arguments/),
which covers all of the basic techniques listed above (and provides examples
for a number of other languages, if you'd like to compare).

As usual, if you want to try playing around with the code yourself, you can
check out the [GitHub Repository](https://github.com/bheisler/raytracer). If you
do, though, be careful with the complexity of the scene you try to render. It's
very easy to reach multi-hour rendering times when you're defining scenes
programmatically. Otherwise, enjoy!
