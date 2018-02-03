+++
date = "2018-02-05T07:00:00-06:00"
description = ""
title = "Criterion.rs v0.2 - HTML, Throughput Measurements, API Changes"
tags = ["Rust", "Benchmarking", "Criterion.rs"]
categories = ["code"]
draft = true
+++

I'm pleased to announce the release of Criterion.rs v0.2, available today. Version 0.2 provides a
number of new features including HTML reports and throughput measurements, fixes a handful of bugs,
and adds a new, more powerful way to configure and construct your benchmarks. It also breaks
backwards compatibility with the 0.1 versions in a number of small but important ways. Read on to
learn more!

## What is Criterion.rs?

Criterion.rs is a statistics-driven benchmarking library for Rust. It provides precise measurements
of changes in the performance of benchmarked code, and gives strong statistical confidence that
apparent performance changes are real and not simply noise. Clear output, a simple API and
reasonable defaults make it easy to use even for developers without a background in statistics.
Unlike the benchmarking harness provided by Rust, Criterion.rs can be used with stable versions of
the compiler.

If you aren't already using Criterion.rs for your benchmarks, check out the [Getting Started
guide](https://japaric.github.io/criterion.rs/book/getting_started.html) or go right to [the GitHub
repo](https://github.com/japaric/criterion.rs).

## New Features

This is only some of the improvements made to Criterion.rs in v0.2 - for a more complete list, see
the [CHANGELOG](https://github.com/japaric/criterion.rs/blob/master/CHANGELOG.md).

### HTML Reports

Criterion.rs now generates an HTML report for each benchmark, including detailed graphs showing the
performance behavior of your code. For an example of the generated report, [click
here](https://japaric.github.io/criterion.rs/book/user_guide/html_report/index.html).
[Gnuplot](http://www.gnuplot.info/) must be installed in order to generate reports.

The reports and other data are now stored in the `target/criterion` directory when you run the
benchmarks, which makes them easier to find and means you no longer need to ignore the `.criterion`
directory.

There is still much work to do on expanding the HTML reports, so stay tuned for further enhancements.

### Criterion.bench

The [`bench`](https://japaric.github.io/criterion.rs/criterion/struct.Criterion.html#method.bench)
function has been added to the `Criterion` struct, along with two new structures -
[`Benchmark`](https://japaric.github.io/criterion.rs/criterion/struct.Benchmark.html) and
[`ParameterizedBenchmark<T>`](https://japaric.github.io/criterion.rs/criterion/struct.ParameterizedBenchmark.html).
These structures provide a powerful builder-style interface to define and configure complex
benchmarks which can perform benchmarks and comparisons that were not possible previously, such as
comparing the performance of a Rust function and an external program over a range of inputs. These
structs also allow for easy per-benchmark configuration of measurement times and other settings.

Example:

```rust
c.bench(
    "Fibonacci",
    Benchmark::new("Recursive", |b| b.iter(|| fibonacci_recursive(20)))
        .with_function("Iterative", |b| b.iter(|| fibonacci_iterative(20))),
);
```

### Throughput Measurements

Criterion.rs can now estimate the throughput of the code under test. By providing a
[`Throughput`](https://japaric.github.io/criterion.rs/criterion/enum.Throughput.html) (for
`Benchmark`) or `Fn(&T) -> Throughput` (for `ParameterizedBenchmark<T>`), you can tell Criterion.rs
how many bytes or elements are being processed in each iteration of your benchmark. Criterion.rs
will then use that information to estimate the number of bytes or elements your code can process per
second.

## Breaking Changes

Unfortunately, some breaking changes were necessary to implement these new features.

### Builder Methods Take self by Value

All of the builder methods on `Criterion` now take `self` by value rather than by mutable reference.
This is to simplify chaining multiple methods after calling `Criterion::default()`, but existing
code which configures a `Criterion` structure may need to be changed or replaced with code that
configures a `Benchmark` instead.

### 'static Lifetime For Closure Types

Most closures passed to Criterion.rs must now have types that live for the `'static` lifetime. Note,
the closures themselves don't need to be `'static`, but their types do.

What does this mean for you? You may need to change your benchmarks from `|b| b.iter(...)` to 
`move |b| b.iter(...)`. This does mean that the closures will take ownership of values used inside
the closure, so you may need to clone or `Rc` shared test data. Simple closures, like those in the
Fibonacci example above, can remain unchanged - this only affects closures which capture values
from their environment.

### Benchmark Parameters Must Implement Debug

Previously, Criterion.rs required the values for parameterized benchmarks to implement the `Display`
trait. This has been changed to require the `Debug` trait instead, as that can be easily derived.

## Thank You

Thank you to Damien Levac (@Proksima), @dowwie, Oliver Mader (@b52), Nick Babcock (@nickbabcock),
Steven Fackler (@sfackler), and @llogiq for suggesting improvements to Criterion.rs since the last
release. I'd also like to thank Alexander Bulaev (@alexbool) and Paul Mason (@paupino) for
contributing pull requests.

If you'd like to see your name up here, or if you have ideas, problems or questions, please consider
contributing to Criterion.rs on [GitHub](https://github.com/japaric/criterion.rs).