+++
date = "2021-01-24T14:30:00-06:00"
description = ""
title = "Criterion.rs v0.3.4 And Iai 0.1.0"
tags = ["Rust", "Benchmarking", "Criterion.rs"]
categories = ["code"]
+++

Today I've released Criterion 0.3.4 and Iai 0.1.0. I'm particularly excited by Iai, so read on to find
out what I've been up to.

## Criterion Updates

The main new feature in this release is that Criterion.rs now has built-in support for benchmarking
async functions.

{{< gist bheisler ee60bf7374d4b1aa9daf73e6ffbc01ee >}}

This feature requires the `async` feature to be enabled. In addition to this, four other features - 
`async-std`, `async-tokio`, `async-smol`, and `async-futures` can be enabled to add support for
benchmarking with the respective futures executors. Additional executors can be plugged in by
implementing a trait.

The other major change in this release is that a number of things have been deprecated and are
slated to be either deleted or will become compile-time optional features in version 0.4.0.

- `Criterion::can_plot` is no longer useful and is deprecated pending deletion in 0.4.0.
- `Benchmark` and `ParameterizedBenchmark` were already hidden from documentation, but are now 
  formally deprecated pending deletion in 0.4.0. Callers should use `BenchmarkGroup` instead.
- `Criterion::bench_function_over_inputs`, `Criterion::bench_functions`, and `Criterion::bench` were
  already hidden from documentation, but are now formally deprecated pending deletion in 0.4.0.
  Callers should use `BenchmarkGroup` instead.
- Three new optional features have been added; "html_reports", "csv_output" and 
  "cargo_bench_support". These features currently do nothing except disable a warning message at 
  runtime, but in version 0.4.0 they will be used to enable HTML report generation, CSV file 
  generation, and the ability to run in cargo-bench (as opposed to [cargo-criterion]). 
  "cargo_bench_support" is enabled by default, but "html_reports" and "csv_output"
  are not. If you use Criterion.rs' HTML reports, it is recommended to switch to [cargo-criterion].
  If you use CSV output, it is recommended to switch to [cargo-criterion] and use the 
  `--message-format=json` option for machine-readable output instead. A warning message will be
  printed at the start of benchmark runs which do not have "html_reports" or "cargo_bench_support"
  enabled, but because CSV output is not widely used it has no warning.

[cargo-criterion]: https://github.com/bheisler/cargo-criterion

For more information on the changes in this release, see the [CHANGELOG](https://github.com/bheisler/criterion.rs/blob/master/CHANGELOG.md)

## Announcing Iai

Late last year, Nelson Elhage posted 
[an article](https://buttondown.email/nelhage/archive/f6e8eddc-b96c-4e66-a648-006f9ebb6678) to his
excellent newsletter on the difficulties of measuring the performance of software. In that article,
he mentioned that the sqlite project runs their benchmarks in
[Cachegrind](https://valgrind.org/docs/manual/cg-manual.html) which gives them extremely precise and
reliable performance measurements.

Itamar Turner-Trauring [followed that up](https://pythonspeed.com/articles/consistent-benchmarking-in-ci/)
with an article suggesting this technique could be used for reliable benchmarking in cloud CI
environments (note the cameo from yours truly!).

In short, cloud CI environments run user builds in virtual machines where the
VMs can be slowed down or even paused for periods of time depending on the load on the service.
This makes them unreliable for precise wall-clock benchmarking, because this can result in large
changes to the measured performance even if the code is exactly the same - differences of as much
as 50% are common! Because of that, it's very difficult to make decisions based on benchmarks
taken in cloud CI systems - if a pull request appears to have regressed the benchmarks, should it
be rejected or was that just noise? Running benchmarks in Cachegrind solves this problem by
measuring something more stable instead - Cachegrind counts the actual instructions and memory
accesses of programs running under it, which gives an extremely precise measurement of the
performance behavior of those programs. Cachegrind is normally used for profiling, but it can be
applied for benchmarking as well.

[Iai](https://github.com/bheisler/iai) is an experimental benchmarking harness that does exactly
that. For right now, it's extremely simple. I'd like to get it into the hands of the community and
get some feedback before I sink too much effort into this idea. The long-term plan is to integrate
Iai with cargo-criterion like Criterion.rs already is and use that to provide plots and history
tracking like cargo-criterion already does for Criterion.rs. I might alternately integrate Iai
into Criterion.rs itself, but for now I think they're different enough that it makes sense to have
them be separate.

I intend Iai to be a complement to Criterion.rs, not a replacement. Wall-clock benchmarks have
their place too - for one thing, Criterion.rs measures the thing you care about (time to execute a
function), rather than a good estimator of the thing you care about. For another, Cachegrind is
only available on Linux and a few other Unix-like operating systems - it is not available for
Windows. If possible, I'd recommend using both Iai and Criterion.rs for your benchmarks. There's a 
full description of the pros and cons of each library in 
[the User Guide](https://bheisler.github.io/criterion.rs/book/iai/comparison.html).

Anyway, using Iai should feel pretty familiar to anyone who's used Criterion. Add the following to
your `Cargo.toml` file:

```
[dev-dependencies]
iai = "0.1"

[[bench]]
name = "my_benchmark"
harness = false
```

Next, define a benchmark by creating a file at $PROJECT/benches/my_benchmark.rs with the following contents:

{{< gist bheisler 79e2da5f5bf86338c9da39bae9416f3a >}}


Finally, run this benchmark with cargo bench. You should see output similar to the following:

```
     Running target/release/deps/test_regular_bench-8b173c29ce041afa

bench_fibonacci_short
  Instructions:                1735
  L1 Accesses:                 2364
  L2 Accesses:                    1
  RAM Accesses:                   1
  Estimated Cycles:            2404

bench_fibonacci_long
  Instructions:            26214735
  L1 Accesses:             35638623
  L2 Accesses:                    2
  RAM Accesses:                   1
  Estimated Cycles:        35638668
```

Iai will track and compare against the last run of a benchmark like Criterion.rs, but it doesn't
yet support HTML reports or more complex historical information.

Thanks to Itamar Turner-Trauring for the formula I used to calculate the "estimated cycles" count.
