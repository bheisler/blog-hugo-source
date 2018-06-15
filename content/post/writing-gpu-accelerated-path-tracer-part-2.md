+++
date = "2019-01-22T16:00:00-06:00"
title = "Writing a GPU-Accelerated Path Tracer in Rust - Part 2"
tags = ["Rust", "GPGPU", "Raytracer", "Pathtracer"]
categories = ["code"]
author = "Brook Heisler"
draft = true
+++

## Tracing Paths

- Short intro to what path tracing is.
- As mentioned last time, Path Tracing is an extension to Ray Tracing. Rather than tracing a single ray through the scene followed by one shadow ray per light source, we instead trace a complete bounce path through the scene back to the light source(s).
- This makes it possible to render indirect lighting in areas that have no direct line-of-sight to a light source, by finding paths from these hidden areas, bouncing off other objects, and ultimately back to a light source.
- In reality, there are infinitely many different paths a photon might have taken to reach your eyes, and it may have bounced arbitrarily many times. 
- We have limits on our computational capability however.
- We can just impose some fixed cap on the number of bounces; in practice, under most circumstances photons lose so much of their energy within a few bounces that afterwards they can be ignored without noticeable effect on the resulting image. This does tend to bias the results slightly, but hopefully not enough to be noticeable.
- To deal with the infinitely many paths, we use a statistical technique called Monte Carlo Integration. In short, we trace many random paths through the scene, determine the brightness from each path, and then average those brightnesses together.
- As you can imagine, this random element can cause a lot of noise in the final image - one pixel's rays might all get lucky and find a direct path to the light (making a bright pixel), while the next pixel's rays might all get hopelessly scattered (making a dark pixel). The more paths we trace, though, the more the averages will tend to converge on the true lighting value.
- More advanced algorithms will try to make the image converge with fewer rays per pixel, to reduce computation time. For now, we'll just implement the basic path tracing algorithm.

## On Surfaces

- It's straightforward enough to bounce rays off of polished glass or metal surfaces - we implemented that in the last set of tutorials. In those cases, there's a single, predictable direction for the new ray that can be calculated from the surface normal and the incoming ray.
- Diffuse surfaces are a bit different, however. They scatter light randomly over a half-sphere above the point of contact, centered on the surface normal.
- To simulate this, we need two things. We need a way to generate random numbers on the GPU (ideally, to generate them very quickly and with good-quality pseudorandom output) and we need some way to use those random numbers to choose a direction vector in the appropriate half-sphere.
- First, let's look at selecting a direction for our bounce ray. I'll come back to the problem of generating random numbers later.

## Hemispheres

- At a high level, the process of selecting a direction is relatively straightforward, but the math gets a bit hairy.
- First, we randomly generate two numbers for the polar coordinates of our vector. For intuition, imagine you wanted to pick a random spot in the sky to point a telescope at. You might generate one random number to indicate which direction you should face, then generate a second number to tell you how high up to look.
- These two numbers are called the azimuth (direction angle, ranges from 0 to 2 * PI) and elevation (angle up into the sky, ranges from 0 to PI / 2).
- Then we need to convert those coordinates into the Cartesian coordinates used by our vectors.
- Normally, this would be done using the following equations:

```
// r here is the radius of the sphere, which in our case is always 1 so I'll ignore it from now on.
azimuth = rand() * PI * 2
elevation = rand() * PI / 2
x = r * sin(elevation) * cos(azimuth)
y = r * cos(elevation)
z = r * sin(elevation) * sin(azimuth)
```

- For efficiency though, it would be nice if we could avoid computing so many trigonometry functions (they tend to be slow).
- Instead, we can simply generate a random number for `cos(elevation)` directly. We need some way to compute `sin(elevation)` given `cos(elevation)`.

```
// We have the following rule from trigonometry:
sin^2(angle) + cos^2(angle) = 1

// Move the cos term to the other side of the equals
sin^2(angle) = 1 - cos^2(angle)

// Take the square root
sin(angle) = sqrt(1 - cos^2(angle))

// cos^2(angle) = cos(angle)^2, and we already have cos(angle), so...
y = rand()
sin(angle) = sqrt(1 - y * y);
```

- This gives us a faster way to generate a point on a hemisphere:

```
azimuth = rand() * PI * 2
y = rand()
sin_elevation = sqrt(1 - y * y)
x = sin_elevation * cos(azimuth);
z = sin_elevation * sin(azimuth);
```

Now we only have to compute two slow trigonometric functions instead of four.

- Now we can generate vectors in a hemisphere centered on the Y axis. We want it to be centered on the normal at the position where the ray intersected the object instead. We can do this by creating a new coordinate system using the surface normal as our 'Y-axis' and creating other vectors to serve as our X and Z axes, then transforming our hemisphere-vector to that system.
- We already have the Y axis of our temporary coordinate system - it's the hit normal. How do we generate the other vectors?
- If we can generate one vector perpendicular to the hit normal, then we can use a cross product to create the third, so we really only need one vector.
- First, lets return to the plane equation from last time:

```
Ax + By + Cz + D = 0
// Alternately, we could use the coordinates of our hit normal N.
N.x * x + N.y * y + N.z * z + D = 0
```

In this case, we don't care about D so we'll just ignore it. Additionally, in this case we're interested in a plane that is perpendicular to the hit normal (our Y axis) and so every point on that plane will have a Y coordinate of zero, so we can ignore that as well.

```
N.x * x + N.z * z = 0
N.x * x = -N.z * z
```

Now, consider - which values of x and z could make this equation true (remember that N.x and N.z are fixed already). Well, if x = -N.z and z = N.x, that would make both sides equal. Another option would be if z = -N.x and x = N.z. We can use this to generate a perpendicular vector to our hit normal. I admit, I don't fully get why this works, but it does. I think we just need to find a vector that points to some point on the plane, since any point on the plane creates a vector perpendicular to the hit normal.

```
let Nt = Vector(N.z, 0, -N.x).normalize();
let Nb = N.cross(Nt);
```

There is one more wrinkle, though. If N.z and N.x are both close to zero then normalizing (which involves dividing by `sqrt(N.x * N.x + N.z * N.z))`) could result in a very long vector, or even a divide-by-zero. We can avoid this by performing a similar trick using the Y coordinate if that's larger than the X coordinate, like so:

```
if (fabs(N.x) > fabs(N.y)) {
    Nt = Vector(N.z, 0, -N.x).normalize();
}
else {
    Nt = Vector(0, -N.z, N.y).normalize();
}
Nb = N.cross(Nt);
```

OK, now we have a coordinate system. To transform our hemisphere vector to this coordinate system, we multiply and sum all of the vectors against the hemisphere vector, like so: (attentive readers may notice that this looks a lot like matrix multiplication):

```
new_ray_direction = Vector(
    hemisphere.x * Nb.x + hemisphere.y * N.x + hemisphere.z * Nt.x,
    hemisphere.x * Nb.y + hemisphere.y * N.y + hemisphere.z * Nt.y,
    hemisphere.x * Nb.z + hemisphere.y * N.z + hemisphere.z * Nt.z,
)
```

## Generating Random Floats

- For this, we need to be able to generate pseudo-random numbers. Normally, I would just use the `rand` crate, but in this case I can't. It does have support for no_std builds, but Xargo needs to have a target JSON file for every crate it builds and `rand` doesn't provide one. I could clone the `rand` crate locally and add one of course, but it's kind of fun to DIY it. I don't need a cryptographically-secure RNG to render pretty pictures, so I'm just going to wing it.
- You can use any random number generator you like. I'm going with an [xorshift](https://en.wikipedia.org/wiki/Xorshift#xorshift) generator because it's small (both in terms of code and memory) and because it's fast.
- This generates a 32-bit unsigned integer as output. We need a floating-point value in the range [0.0-1.0]. We could simply divide by the maximum value of a u32. Or, we could do some [evil floating-point bit-level hacking](https://en.wikipedia.org/wiki/Fast_inverse_square_root#Overview_of_the_code) to make it go faster. I know which one I'm going with!
- Standard floating-point numbers are made up of a sign bit, some number of exponent bits and the rest are mantissa bits. The sign bit we already know; it should be positive. You can think of the exponent bits as selecting a window between two consecutive power-of-two integers, and the mantissa bits as selecting an offset within that window (see [Floating Point Visually Explained](http://fabiensanglard.net/floating_point_visually_explained/) for more details).
- Therefore, if we can generate a random mantissa section and set the sign and exponent bits to the right value, we can generate a random float without doing a floating-point division (which is somewhat expensive). (side note - this is silly levels of micro-optimization, especially considering that we haven't even tried to optimize our algorithm yet. I'm just doing this for fun, not because I think the extra performance is actually worth it.) (second side note: This algorithm was inspired by https://xor0110.wordpress.com/2010/09/24/how-to-generate-floating-point-random-numbers-efficiently/)
- We know the right window for our numbers - [0.0 to 1.0]. However, it's easiest to do this if we select the window of the right width to start with, so I'll go with generating a number in the range of [1.0 to 2.0] and then subtract 1.0 from it afterwards.
- For IEEE standard single-precision floating points, this gives us a fixed bit pattern for the first 9 bits, followed by 23 random bits.
- I used a floating-point converter I found on Google to get the correct bit pattern for the sign and exponent bits - 0x3F800000. Then we just mask out the lower 23 bits of our random integer (mask is 0x007FFFFF) and combine. Finally, we transmute the resulting bit pattern into a 32-bit float, subtract 1.0 and return.

```
fn random_float(seed: &mut u32) -> f32 {
    let mut x = *seed;
    x ^= x >> 13;
    x ^= x << 17;
    x ^= x >> 5;
    *seed = x;
    let float_bits = (x & 0x007FFFFF) | 0x3F800000;
    let float: f32 = unsafe { ::core::mem::transmute(float_bits) };
    return float - 1.0;
}
```

Some quick testing confirms that the output is at least approximately uniform, so it's probably good enough for our purposes. One neat thing about this trick is that it's customizable; if you want numbers in the range [-1.0, 1.0] you can use 0x40000000 instead of 0x3F800000 to select the exponent for the [2.0, 4.0] range and then subtract 3.0.

## Putting it All Together

- Now we can create a random scatter direction, so we can have our backwards light rays bounce realistically when they intersect an object. We need to bounce each ray through the scene, adding the emission of any glowing objects it encounters.
- On the CPU, we'd just do this recursively. We might have a function to trace a ray and return the color of the light coming from that direction (which would then call itself recursively). We'd multiply that light by the albedo and color of the object, a factor based on the angle of incidence and maybe a fudge factor or two, and return it.
- CUDA code technically can do recursion, but in my case doing so causes all of my kernel launches to fail with an `OUT_OF_RESOURCES` error. I can only guess why; CUDA doesn't really explain itself very well.
- Anyway, I'll have to do this iteratively, then. This is a bit tricky to think about. I keep an accumulator to hold the color for the path as it's being traced, and a mask. The mask is multiplied by the emission of each intersected object before that emission is added to the accumulator. The mask represents the accumulated absorption of all of the objects the path has bounced off of up until now.
- Some examples are in order. If the ray we trace directly intersects a glowing object, the mask will be (1.0, 1.0, 1.0), so the glow color of the object will be added directly to the accumulator.
- If we bounce off a green (0.0, 1.0, 0.0) object first, the mask picks up the green color, and it might be set to (0.0, G, 0.0), where G is < 1.0. The reason why the mask is less bright than the color of the object has to do with the albedo of the object (how much of the incoming light does it reflect away) and the angle of incidence of that light. If the ray scatters off of the green object and then hits a light, we multiply the glow color of the object by the mask and add it to the accumulator.
- Then we generate a new scatter ray and repeat the loop until we reach a maximum number of bounces.

```

unsafe fn get_radiance(
    x: u32,
    y: u32,
    width: u32,
    height: u32,
    fov_adjustment: f32,
    materials: *const Material,
    polygons: *const Polygon,
    polygon_count: usize,
    random_seed: &mut u32,
) -> Color {
    let mut color_mask = WHITE;
    let mut color_accumulator = BLACK;

    let mut current_ray = Ray::create_prime(
        x as f32,
        y as f32,
        width as f32,
        height as f32,
        fov_adjustment,
    );

    let mut i = 0;
    while i < BOUNCE_CAP {
        if let Some((distance, hit_poly)) = intersect_scene(&current_ray, polygon_count, polygons) {
            let closest_polygon: &Polygon = &*polygons.offset(hit_poly);

            let hit_normal = closest_polygon.normal;
            let hit_point = current_ray
                .origin
                .add(current_ray.direction.mul_s(distance));
            // Back off along the hit normal a bit to avoid floating-point problems.
            let hit_point = hit_point.add(hit_normal.mul_s(FLOATING_POINT_BACKOFF));

            let bounce_direction = create_scatter_direction(&hit_normal, random_seed);
            current_ray = Ray {
                origin: hit_point,
                direction: bounce_direction,
            };

            let material_idx = closest_polygon.material_idx as isize;
            let material = &*materials.offset(material_idx);

            color_accumulator = color_accumulator.add(material.emission.mul(color_mask));

            // Lighting = emission + (incident_light * color * incident_direction dot normal * albedo * PI)
            let cosine_angle = bounce_direction.dot(hit_normal);
            let reflected_power = material.albedo * ::core::f32::consts::PI;
            let reflected_color = material.color.mul_s(cosine_angle).mul_s(reflected_power);

            // The 2.0 is a fudge factor to make the images brighter.
            color_mask = color_mask.mul(reflected_color).mul_s(2.0);
        } else {
            return color_accumulator;
        }
        i += 1;
    }
    return color_accumulator;
}
```

- Now that we have code to sample the color at a pixel, we need to average those colors together. Since our scatter rays may not ever intersect with a light source, there would be a huge amount of noise in our image if we only sampled each pixel once. Instead, path tracers trace many (hundreds or thousands) of scattered paths through the scene and average all of the resulting samples together.
- This raises another problem. Remember the 3-second kernel execution time limit I mentioned in the last post? There's no way my card can render a decent-sized image with thousands of paths per pixel in 3 seconds. (footnote: In fact, currently it takes several hours, though I plan to make it faster soon). It can't even come close to tracing enough rays in one 3-second window to make even a small part of the image converge.
- To work around this, I render each block of the image many times, accumulating the results in the image buffer. In this way, I can render an arbitrarily complex scene (within limits, anyway; it has to be able to complete at least one sample for each pixel in time) given enough time.

```
#[no_mangle]
pub unsafe fn trace_inner(
    x: u32,
    y: u32,
    width: u32,
    height: u32,
    round: u32,
    fov_adjustment: f32,
    image: *mut Color,
    polygons: *const Polygon,
    polygon_count: usize,
    materials: *const Material,
    material_count: usize,
) {
    let i = (y * width + x) as isize;
    if x < width && y < height {
        let mut random_seed: u32 = RANDOM_SEED
            ^ ((x << 16) + ((polygon_count as u32) << 12) + (width << 23) + (height << 28)
                + (round << 5) + y);

        let mut color_accumulator = *image.offset(i);
        let mut ray_num = 0;
        while ray_num < RAY_COUNT {
            color_accumulator = color_accumulator.add(
                get_radiance(
                    x,
                    y,
                    width,
                    height,
                    fov_adjustment,
                    materials,
                    polygons,
                    polygon_count,
                    &mut random_seed,
                ).mul_s(1.0 / (RAY_COUNT * ROUND_COUNT) as f32),
            );
            ray_num += 1;
        }

        *image.offset(i) = color_accumulator;
    }
}
```

- As I said though, this takes hours. There are ways to speed it up, though, and I'll cover that in the next post.

## Conclusion

conclusiony-stuff goes here.