+++
date = "2019-08-25T10:30:00-06:00"
description = ""
title = "Criterion.rs v0.3 - Custom Measurements, Profiling Hooks, Custom Test Framework, API Changes"
tags = ["Rust", "Benchmarking", "Criterion.rs"]
categories = ["code"]
+++

I'm pleased to announce the release of Criterion.rs v0.3, available today. Version 0.3 provides a
number of new features including preliminary support for plugging in custom measurements (eg. 
hardware timers or POSIX CPU time), hooks to start/stop profilers, a new `BenchmarkGroup` struct
that provides more flexibility than the older `Benchmark` and `ParameterizedBenchmark` structs, and
an implementation of a `#[criterion]` custom-test-framework macro for those on Nightly.

## What is Criterion.rs?

Criterion.rs is a statistics-driven benchmarking library for Rust. It provides precise measurements
of changes in the performance of benchmarked code, and gives strong statistical confidence that
apparent performance changes are real and not simply noise. Clear output, a simple API and
reasonable defaults make it easy to use even for developers without a background in statistics.
Unlike the benchmarking harness provided by Rust, Criterion.rs can be used with stable versions of
the compiler.

If you aren't already using Criterion.rs for your benchmarks, check out the [Getting Started
guide](https://bheisler.github.io/criterion.rs/book/getting_started.html) or go right to [the GitHub
repo](https://github.com/bheisler/criterion.rs).

## New Features

These are only some of the improvements made to Criterion.rs in v0.3.0 - for a more complete list, see
the [CHANGELOG](https://github.com/bheisler/criterion.rs/blob/master/CHANGELOG.md).

### Custom Measurements

Criterion.rs now has basic support for plugging in custom measurements to replace the default
wall-clock time measurement. This has been a highly-requested feature during the lifetime of 0.2.0,
so I look forward to seeing all the neat things people use it for.

### Profiler Hooks

Some profiling tools require the programmer to instrument their code with calls to start and stop
the profiler. Criterion.rs now provides hooks for benchmark authors to plug in their preferred
profiler so that it can be used in `--profile-time` mode, without having to constantly recompile
the benchmarks.

### Added the `BenchmarkGroup` Type

The older `Benchmark` and `ParameterizedBenchmark` structs were used to group together related
benchmarks so that Criterion.rs could generate summaries of the measurements comparing different
functions on different inputs. Unfortunately, they could be very limiting. It was not possible
to change the benchmark configuration based on the input or the function being tested (for example,
to reduce the sample count on long-running benchmarks over large inputs while keeping the higher
sample count for smaller inputs). It was also awkward to benchmark over multi-dimensional input
ranges, they didn't allow much programmer control over the benchmark IDs, etc.

After some re-thinking of the problem, I realized that a much simpler, more-flexible design was
possible, so I built `BenchmarkGroup`. The older structs still exist and still work, but will be
deprecated sometime during the lifetime of 0.3.0 and removed in 0.4.0. 

Examples:

{{< gist bheisler 9bb536a426baa0cbc75f2a6c665d8400 >}}

### Custom Test Framework

Nightly-compiler users can now add a dependency on `criterion_macro` and use `#[criterion]`
to mark their benchmarks instead of using the `criterion_group!/criterion_main!` macros.

Examples:

{{< gist bheisler eb81b0d81e61a83f10d31ca663b37007 >}}

## Breaking Changes

Unfortunately, some breaking changes were necessary to implement these new features.

### The format of the `raw.csv` file has changed

Some additional columns were added to include throughput information. Also, `sample_time_nanos`
has been split into `sample_measured_value` and `unit` to accommodate custom measurements.

### External Program Benchmarks have been removed.

This feature was never used enough to justify the maintenance burden, so it was deprecated in 0.2.6
and removed in 0.3.0. With some extra effort on the part of the benchmark author, the new
`iter_custom` timing loop can be used to implement external program benchmarks.

### Throughput has been expanded to u64

Throughputs previously contained a u32 value representing the number of bytes or elements processed
by an iteration of the benchmark. This has been expanded to u64 to allow for extremely large
iterations.

## Thank You

Thank you to all of the many folks who have contributed pull requests or ideas and suggestions to
Criterion over the last few years.

Also, thank you to all you folks who use Criterion.rs for their benchmarks.
