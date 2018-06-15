+++
date = "2019-01-22T16:00:00-06:00"
title = "Writing a GPU-Accelerated Path Tracer in Rust - Part 1"
tags = ["Rust", "GPGPU", "Raytracer", "Pathtracer"]
categories = ["code"]
author = "Brook Heisler"
draft = true
+++

Well, it's that time again. I've decided to do a second series of articles on raytracing in Rust
following on from my previous series. This time, there are a few new twists - First and foremost,
I'll be doing all of the rendering on a GPU using Accel see (TODO: Insert link) my previous post on
Accel. I thought this would be a good project for learning about GPU programming, see.

Second, this time around I want to write a path tracer, rather than a ray tracer.

You don't need to know anything about GPU programming to follow along - I'll explain things as
needed. If you intend to run your code on the GPU though, you should probably read that post about
Accel. As before, I will assume that you're familiar with the basics of linear algebra (you should
know about vectors and what the dot and cross products are). I'll also assume that you've read my
previous series.

## Path Tracing

A path tracer is similar to a raytracer in that it traces rays of light backwards from the camera
through a scene. Unlike a raytracer, however, a path tracer traces many rays - often thousands -
for each pixel. The rays are scattered randomly off of the objects they intersect until they reach
a light source, leave the scene entirely, or reach some predetermined bounce limit. Each ray is
colored according to the objects it bounced off of and the light source it reached, and the final
color of a pixel is the average of all rays traced through it.

This is helpful because it more-accurately reflects the behavior of real light; what our eyes see
is the sum total of all light received from a particular point in the world; those photons took
many different paths and were colored by many different objects on their way to that point. For
example, when you have a brigh red object in bright light, it makes other nearby objects appear to
glow red with reflected light. Another example is when a sunbeam shines through a glass object, you
can see a pattern of light and dark where the object focuses some of the rays (these patterns are
called 'caustics'). Path tracing makes it easy to render these effects where ray tracing does not.

Of course, that randomness has a down-side as well - it can produce very noisy images if the number
of rays per pixel is not large enough (We say that the image has converged when there are enough
rays to remove visible noise). And of course, tracing hundreds or thousands of rays through each
pixel takes much more computation than tracing one, so path tracers take much longer to render an
equivalently-sized image than a comparable ray tracer. In particular, although it's true that it's
easy to render caustics with a path tracer, they tend to be even more noisy than the rest of the
scene and so require an even larger number of rays per pixel. More advanced algorithms like
Bi-Directional Path Tracing seek to speed up rendering times by making the image converge with
fewer rays. I'll just be implementing the basic path tracing algorithm here though.

As one commenter pointed out last time, Pixar's RenderMan system uses advanced path-tracing
algorithms, not ray-tracing, to render their movies. My apologies, and I hope that commenter's need
for pedantic technical correctness has been satisfied.

## Basics of GPU Acceleration

Raytracing is a good problem for GPU acceleration because it's massively parallel - every pixel (or
in a path tracer, potentially every ray), can be computed in parallel with every other pixel. GPUs
are fast because they can efficiently run thousands or tens of thousands of parallel threads. Even
though each individual thread is significantly slower than a CPU thread, working together they can
do a lot of work quickly.

It's not necessary to know a whole lot about GPU acceleration for this post (and I'm certainly no
expert myself) but it is useful to know about memory coalescing. I'm mostly going to ignore
efficiency in this post. I'll make it work, then I'll make it fast later on. I'll explain more
about the factors involved in writing efficient GPU code when they become more relevant.

## Setting the Scene

My previous ray tracer handled only spheres and planes. I was kind of bored with that, so I decided
to make this one work with polygon meshes instead. Crates.io already has a
[library](https://crates.io/crates/obj) for parsing the Wavefront OBJ format. The OBJ format uses a
compressed representation where each polygon is simply a list of indexes into a position array. I
decided to expand that into a simpler structure where each polygon simply contains three 3D vectors
representing the vertices on the basis that this is easier to work with, and it avoids the extra
indirection of looking up the vertex index, then using that to look up the vertex. This structure
will probably be quite inefficient, but it's good enough for now. I may opt to rework this later.

The meshes that I'm using only contain triangles, but some meshes contain quads or even more
complex polygons. We'll convert those more complex polygons to triangles for simplicity. It's
not hard to convert complex polygons to triangles. You take the first vertex, then iterate over
the remaining vertices using a two-element sliding window. This produces a series of three-vertex
triangles. See the following pseudocode:

```
vertex1 = polygon[0]
for (int k = 1; k < polygon.length - 1; k++) {
    vertex2 = polygon[k]
    vertex3 = polygon[k+1]
    add_triangle(vertex1, vertex2, vertex3)
}
```

Triangles are convenient for us because all three points of a triangle must lie in the same plane.
This will be important once we start intersecting triangles against them. For generating prime
rays, I simply re-used the prime ray code from the old ray tracer. I made some changes to simplify
it, but if you want to you could just copy the old code. This is why it's handy to use Accel to
program my GPU - I can keep using Rust, and even re-use old Rust code, without having to rewrite
it in C/C++ or something else.

## Ray-Triangle Intersection Test

As mentioned earlier, the nice thing about triangles is that all points lie in the same plane. This
is helpful for the intersection test, since we can break it up into two tests - does the ray
intersect the plane at all, and if so, does it intersect the plane inside the triangle?

Step 1 is to calculate the normal of the plane. Recall that performing the cross product of two
vectors produces a new vector perpendicular to both of them. To generate the normal of a plane,
therefore, one can simply take the cross product of two vectors in that plane. We can generate two
vectors in the plane of the triangle by subtracting the vertices from each other like so:

```
let a = v1 - v0;
let b = v2 - v0;

let normal = a.cross(b).normalize();
```

Depending on which vertices we use in which order, we can get two different normals. This makes 
sense; a plane has two sides and therefore two opposing normal vectors. Which one we see depends on
whether the vertices were stored in clockwise or counterclockwise order. OBJ files are supposed to
always be in counterclockwise order, which is the same convention that Scratchapixel uses, so I
think we're OK here.

Last time, I passed over trying to explain how the plane-intersection test works. I'm going to give
it a try now. I'll admit that I can't think of a good intuitive geometric explanation of why this
works, so I'll just explain the math.

Planes are defined by an equation `Ax + By + Cz + D = 0`. (Footnote: Some sources use `Ax + By + Cz
= D`. This is just a different convention. You can convert between the two by negating D, but
Scratchapixel uses the former equation so I will as well.)

Speaking of Scratchapixel, their derivation and implementation of this equation
([here](https://www.scratchapixel.com/lessons/3d-basic-rendering/ray-tracing-rendering-a-triangle/ray-triangle-intersection-geometric-solution))
is wrong. This confused me for *hours* before eventually I found another source that derived it
correctly. I was then confused for more hours because that source used the other convention so I
tried to figure out why that worked and Scratchapixel's didn't. Eventually I did the derivation
myself on paper and spotted the mistake. I'll give the correct version.

This plane equation is equivalent to `N dot P + D = 0` where N is a normal of the plane 
`(A, B, C)`, P is any point on that plane `(x, y, z)`, and D is a constant for the smallest distance
between the plane and the origin. In addition, we have the ray equation `Ray(t) = O + tR` where O
is the origin of the ray, R is the direction of the ray, and t is some distance along that
direction. If the ray intersects the plane, we know that the intersection point must be a point in
the plane, so we can substitute Ray(t) for P get the following equation:

```
N dot Ray(t) + D = 0
N dot (O + tR) + D = 0
N dot O + t(N dot R) + D = 0

// We can rearrange this to solve for t...
N dot O + t(N dot R) = -D
t(N dot R) = -D - (N dot O)
t = (-D - (N dot O))/(N dot R)
```

We have N - we calculated the normal earlier. We have O and R, because those are the components of
the ray we're tracing. We need to calculate D before we can get t. Fortunately, we can calculate D
using N and *any* point on the plane. The vertices of the triangle are also points on the plane, so
we can plug one of the vertices (I'll use the first one, but any of them will work) into the
equation and solve for D like so:

```
N dot v0 + D = 0
D = -(N dot v0)
```

(This is where Scratchapixel goes wrong; they forgot the negative sign)

Thus, we have our pseudocode for the intersection of a ray and a plane:

```
let D = -(normal.dot(polygon.vertices[0]));
let t = (-D - (normal.dot(ray.origin))/(normal.dot(ray.direction));

// Or, for simplicity, we can remove the double-negation of D
let neg_D = normal.dot(polygon.vertices[0]);
let t = (neg_D - (normal.dot(ray.origin))/(normal.dot(ray.direction));
```

Finally, we can plug t back into the ray equation to get the intersection point:

```
let p = ray.origin + t * ray.direction;
```

There are a few corner cases we need to deal with, however. If the ray is parallel to the triangle, the dot-product of the normal and the ray direction will be zero and we'll get a divide-by-zero error. However, this is actually convenient for us, since in that case we know the ray will not intersect the triangle (or even intersect the plane at all) so we can just return no-intersection in that case.

Additionally, we need to check if the distance t is negative. If so, this means that the triangle's plane is actually behind the origin of the ray, and so it wouldn't really intersect. Again, all we have to do is check for that and return no-intersection.

## Triangle Intersection Part 2

Now that we've found the point where the ray intersects the plane defined by a triangle, we need to
check if that point is actually inside the triangle. This is another one where it's hard to give an
intuitive explanation for why this works. First, we define a test to see if a point is on the left
side or right side of a vector.

Consider the following image:

TODO: insert image

We can use the cross product and dot product to determine if the vectors B and B' are on the left
or right side of the vector A. For this example, let's use the following numbers:

```
A = (0, 1, 0)
B = (-1, 1, 0)
B' = (1, 1, 0)
```

Recall that the cross product is defined like so:

```
C.x = A.y * B.z - A.z * B.y
C.y = A.z * B.x - A.x * B.z
C.z = A.x * B.y - A.y * B.x
```

We'll calculate C = `A.cross(B)` and C' = `A.cross(B')`. Since A.z, B.z and B'.z are all zero in
this case, you can see that C.x and C'.x will also be zero. The same is true for C.y and C'.y. For
C.z and C'.z, however...

```
C.z = 0 * 1 - 1 * -1
    = 0 - (-1)
    = 1

C'.z = 0 * 1 - 1 * 1
     = 0 - 1
     = -1
```

Thus, C = (0, 0, 1) and C' = (0, 0, -1). In keeping with our convention that negative-Z means "into
the screen", this means that for this example C points out of the screen while C' points into it.
This gives us our test; B is on the left side of A and so the cross product points out of the
screen, where B' is on the right side of A so the cross product points into the screen. We need
this to handle arbitrary planes in 3D space, though, not just the 2D plane of the screen. To do
this, we can calculate the dot product of C and C' against the triangle's normal vector N. N and C
point in the same direction (in this case, out of the screen) so their dot product will be
positive. N and C' point in opposite directions, so their dot product will be negative.

Putting that all together, we get our left-side test: `left = A.cross(P).dot(N) > 0` where A and P
are the vector and point we want to check and N is the surface normal of the plane.

Now that we have that, determining if the intersection point is inside our triangle is straightforward - if the point is to the left of all three edges of the triangle, it's inside the triangle.

TODO: Insert image

And finally, we have an intersection test that we can implement in code. As a side note, this
left-of-all-edges test works on all convex polygons, not just triangles.

```
fn intersection_test(polygon: &Polygon, ray: &Ray) -> Option<f32> {
    // Step 1: Find P (intersection between triangle plane and ray)

    let n = polygon.normal;

    let n_dot_r = n.dot(ray.direction);
    if unsafe { intrinsics::fabsf32(n_dot_r) } < EPSILON {
        // The ray is parallel to the triangle. No intersection.
        return None;
    }

    // Compute -D
    let neg_d = n.dot(polygon.vertices[0]);

    // Compute T
    let t = (neg_d - ray.origin.dot(n)) / n_dot_r;
    if t < 0.0 {
        // Triangle is behind the origin of the ray. No intersection.
        return None;
    }

    // Calculate P
    let p = ray.origin.add(ray.direction.mul_s(t));

    // Step 2: is P in the triangle?

    // Is P left of the first edge?
    let edge = polygon.vertices[1].sub(polygon.vertices[0]);
    let vp = p.sub(polygon.vertices[0]);
    let c = edge.cross(vp);
    if n.dot(c) < 0.0 {
        return None;
    } // P is right of the edge. No intersection.

    // Repeat for edges 2 and 3

    let edge = polygon.vertices[2].sub(polygon.vertices[1]);
    let vp = p.sub(polygon.vertices[1]);
    let c = edge.cross(vp);
    if n.dot(c) < 0.0 {
        return None;
    }

    let edge = polygon.vertices[0].sub(polygon.vertices[2]);
    let vp = p.sub(polygon.vertices[2]);
    let c = edge.cross(vp);
    if n.dot(c) < 0.0 {
        return None;
    }

    // Finally, we've confirmed an intersection.
    Some(t)
}
```

## A Diversion

It's about at this point that my path tracer started crashing mysteriously, and even forcing a
display reset. I initially suspected a segfault or something similar (I'm using raw pointers here
so Rust can't necessarily prevent those), but I checked all of my code and I couldn't find one.
Then I noticed that it worked - but only if I rendered a much smaller number of polygons.

After some internet searching, I discovered that most operating systems - including Linux and
Windows (which is what I'm developing on) - have a watchdog timer running. If the GPU is busy and
unable to repaint the screen for more than a few seconds, the operating system forcibly resets it,
killing my path-tracer kernel in the process. There are some ways around this, but they involve
changing registry settings or setting the graphics card into a different mode where it isn't
available for painting the screen, but I only have the one GPU and I don't like messing with the
registry when I don't have to. For now, I'll just render a simpler mesh at a lower resolution;
later on, I'll break up the image into smaller blocks so that the card can render each block inside
the time limit. Or maybe I'll just make my code run fast enough to complete inside the time limit.

## First Image

Whew! After all of that, I threw together some basic code to render a simple image. It's simple
code for now; it just traces one ray for each pixel and sets the color to bright green if it hits a
polygon. In the next post, I'll develop this code from a simple ray tracer into a path tracer to do
lighting.

Image: path_tracer_green_teapot.png

What's that ~~Pokemon~~ object? The [Utah Teapot](https://en.wikipedia.org/wiki/Utah_teapot) as
seen from above!

## Positioning

TODO: Write some stuff about positioning objects with matrices.

## Conclusion

blah blah blah conclusion stuff