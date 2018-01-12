+++
date = "2018-01-09T16:00:00-06:00"
description = ""
title = "Benchmarking In Stable Rust With Criterion.rs"
tags = ["Rust", "Benchmarking", "Criterion.rs"]
categories = ["code"]
draft = true
+++

intro:

When I initially announced the release of Criterion.rs, I didn't expect that
there would be so much demand for benchmarking on stable Rust. Now, I'd like to
announce the release of Criterion.rs 0.1.2, which supports the stable compiler.
This post is an introduction to benchmarking with Criterion.rs and a discussion
of reasons why you might or might not want to do so.

# Getting Started with criterion.rs

Honestly, you can basically just copy/paste the stuff from the readme here.

# Converting libtest benchmarks to Criterion.rs

Insert example here. The same example should be added to the Criterion.rs docs.

# The Pitch - Why You Might Want to Use Criterion.rs

There are a number of reasons to use Criterion.rs.

The biggest one, the one that initially drew me to it and led to me
volunteering to take over maintenance, is the statistical confidence it
provides. libtest gives a number and a confidence interval of some sort, but I
couldn't even tell if that number is higher or lower than it was the last time
I ran the benchmarks. Even if it was, how could I tell if that change was due
to random noise or a change in the performance of the code? I've used
Criterion.rs to benchmark and optimize my own projects and every time I've seen
it show a statistically-significant optimization or regression it's been real.
It's almost fun, tweaking the code and running the benchmarks to see what
happened. I've never gotten into that sort of flow with libtest.

- Actively maintained, where bencher and libtest are not adding new features.
- Stable-compatible, unlike libtest.
- Automatically compares with previous run
- More statistical information is available
- More stable results
- Graphical plots, which will likely be expanded in the future to a detailed
  HTML report

# The Anti-Pitch - Why You Might Prefer Bencher or libtest
- Libtest benchmarks execute quicker
- Interface to bencher is likely to be more stable
- libtest has a fully-functional black_box
- libtest is the only option for benchmarks inside your `src` directory
- libtest is easier to use

# Next Steps

Although Criterion.rs now supports stable Rust, that doesn't mean that it
itself is stable, or even feature-complete. I certainly plan to continue
polishing and expanding on what Criterion.rs already provides. If you'd like to
help with that effort, or if you'd like to make suggestions, feature requests
or bug reports, please check out [the repository on
GitHub](https://github.com/japaric/criterion.rs).

In addition, I intend to work with the Rust team to define and implement the
necessary changes to Cargo and rustc to use alternate test and benchmark
frameworks. This would make it as seamless to use Criterion.rs as it already is
to use libtest, and will hopefully allow the community to experiment with a
variety of ways to support testing and benchmarking.