+++
date = "2018-01-12T19:00:00-06:00"
description = ""
title = "Benchmarking In Stable Rust With Criterion.rs"
tags = ["Rust", "Benchmarking", "Criterion.rs"]
categories = ["code"]
+++

When I initially announced the release of Criterion.rs, I didn't expect that
there would be so much demand for benchmarking on stable Rust. Now, I'd like to
announce the release of Criterion.rs 0.1.2, which supports the stable compiler.
This post is an introduction to benchmarking with Criterion.rs and a discussion
of reasons why you might or might not want to do so.

## What is Criterion.rs?

Criterion.rs is a benchmarking library for Rust that aims to bring solid
statistical confidence to benchmarking Rust code, while maintaining good
ease-of-use, even for programmers without a background in statistics. It's
already available on [Crates.io](https://crates.io/crates/criterion) and on
[GitHub](https://github.com/japaric/criterion.rs).

It was originally written by [@japaric](https://github.com/japaric/), but was
never released on Crates.io. I ([@bheisler](https://github.com/bheisler))
volunteered to take over maintenance and development a few months ago, and I
published the first version of Criterion.rs to Crates.io in December 2017.

## Getting Started with Criterion.rs

To start with Criterion.rs, add the following to your `Cargo.toml` file:

```toml
[dev-dependencies]
criterion = "0.1.2"

[[bench]]
name = "my_benchmark"
harness = false
```

Next, define a benchmark by creating a file at `$PROJECT/benches/my_benchmark.rs` with the following contents.

{{< gist bheisler 2da10e7aaac3011ce1d6328e3a4ffdce >}}

Finally, run this benchmark with `cargo bench`. You should see output similar to the following:

```
     Running target/release/deps/example-423eedc43b2b3a93
fib 20                  time:   [26.029 us 26.251 us 26.505 us]
Found 11 outliers among 99 measurements (11.11%)
  6 (6.06%) high mild
  5 (5.05%) high severe
```

See the [Getting Started](https://japaric.github.io/criterion.rs/book/getting_started.html) guide for more details.


## Converting libtest benchmarks to Criterion.rs

We'll start with this benchmark as an example:

{{< gist bheisler 61efe654cf235acab9966f8e3e55a5c3 >}}

The first thing to do is update the `Cargo.toml` to disable the libtest
benchmark harness:

```toml
[[bench]]
name = "example"
harness = false
```

The next step is to update the imports:

```rust
#[macro_use]
extern crate criterion;
use criterion::Criterion;
```

Then, we can change the `bench_fib` function. Remove the `#[bench]` and change
the argument to `&mut Criterion` instead. The contents of this function need to
change as well:

```rust
fn bench_fib(c: &mut Criterion) {
    c.bench_function("fib 20", |b| b.iter(|| fibonacci(20)));
}
```

Finally, we need to invoke some macros to generate a main function, since we
no longer have libtest to provide one:

```rust
criterion_group!(benches, bench_fib);
criterion_main!(benches);
```

And that's it! The complete migrated benchmark code is below:

{{< gist bheisler 45675855d119ad6f03fa94a5247466fe >}}

## The Pitch - Why You Might Want to Use Criterion.rs

There are a number of reasons to use Criterion.rs.

The biggest one, the one that drew me to it in the first place, is the
statistical confidence it provides. libtest gives a number and a confidence
interval of some sort, but I cant't even tell if that number is higher or
lower than it was the last time I ran the benchmarks. Even if it is, how could
I tell if that change was due to random noise or a change in the performance of
the code? I've used Criterion.rs to benchmark and optimize my own projects and
every time I've seen it show a statistically-significant optimization or
regression it's been real. It's almost fun, tweaking the code and running the
benchmarks to see what happened. I've never gotten into that sort of flow with
libtest.

Another big reason is that Criterion.rs is actively maintained and developed.
libtest is not, and the description of the bencher crate on GitHub declares
that new features will not be added. Indeed, it instructs the reader to "Go
build a better stable benchmarking library." I hope Criterion.rs is that
library.

Criterion.rs produces more statistical information than libtest, and generates
helpful charts and graphs to make it more easily understandable to the user.
Additionally, it automatically compares the results of one run with the
previous, without needing to install cargo-benchcmp or manually save benchmark
results to files.

Finally, Criterion.rs is compatible with stable builds of Rust, where libtest is
not.

## The Anti-Pitch - Why You Might Prefer libtest

With all that said, I would also like to explain some reasons why Criterion.rs
might not be right for everyone.

For example, libtest benchmarks execute much more quickly than
Criterion.rs benchmarks, especially the small and fast benchmarks. A small
libtest benchmark function can run to completion in less than a second, where
Criterion runs for (by default) at least 8 seconds plus analysis time. If your
project lends itself to many small benchmarks, you'd need to configure
Criterion.rs to run shorter tests, where you wouldn't with libtest.

The corollary to active development is that Criterion.rs' API is not yet fully
stablized, where libtest isn't likely to change.

libtest is also more seamless to use than Criterion.rs. You don't need to mess
around with your `Cargo.toml` file to use libtest benchmarks, they just work.
Along the same lines, libtest has the `test::black_box` function to prevent
unwanted constant folding, which Criterion.rs can only approximate for now.
Finally, libtest is the only option for benchmarks within your main crate -
both Criterion.rs and bencher can only be used in the `benches` folder at
present.

## Next Steps

I hope I've convinced you to give Criterion.rs a look. I'm excited for the
future of this project and of Rust as a whole, and I hope you are too.

Although Criterion.rs now supports stable Rust, that doesn't mean that it
itself is stable, or even feature-complete. I certainly plan to continue
polishing and expanding on what Criterion.rs already provides. If you'd like to
help with that effort, or if you'd like to make suggestions, feature requests
or bug reports, please check out [the repository on
GitHub](https://github.com/japaric/criterion.rs).

In addition, I hope to work with the Rust team to help define and implement the
necessary changes to Cargo and rustc to use alternate test and benchmark
frameworks. This would make it as seamless to use Criterion.rs as it already is
to use libtest, and will hopefully allow the community to experiment with a
variety of ways to support testing and benchmarking.