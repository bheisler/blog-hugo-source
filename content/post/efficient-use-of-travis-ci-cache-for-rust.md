+++
date = "2020-08-03T18:00:00-06:00"
description = ""
title = "Efficient Use of Travis-CI's Cache For Rust Builds"
tags = ["Rust"]
categories = ["code"]
+++

A while ago, I complained on Reddit about the Travis-CI build times for my Rust crates.
Aleksey Kladov, better known in the Rust community as "matklad", 
[responded](https://www.reddit.com/r/rust/comments/hjx82b/compiler_team_roadmap_20202021/fwrrb62/?context=3) to mention that
Travis-CI's caching behavior is... suboptimal for Rust crates and gave me a way to fix it.

I figure there are probably other Rust developers out there who aren't aware of this, so I'm
writing a short post to explain it. All credit for noticing this problem and the solution goes to
matklad, I'm just sharing it.

As a side note, I have thought about looking at other CI solutions, but haven't bothered to make
the switch. This isn't about comparing CI providers, just a useful configuration tweak that other
Rust developers might find helpful.

## The Problem

Rust builds are notoriously slow, especially when compiling from a clean slate. This is less true
than it once was, but it's still slow enough to be a significant problem for CI systems. Travis-CI's
documentation encourages users to enable build caching in their CI configuration; they even have
a built-in `rust` profile for their caching system that configures the caching to save your `target`
directory (among a few others). In theory, this enables you to save the compiled artifacts of your
build from run to run and avoid wasting time compiling them over and over when nothing has changed.

Documentation is sparse on the caching system, but from observation the way it seems to work is that
at the end of a run, a handful of directories are scanned for new or changed files. If any are found
then all of the directories are packaged into a tarball or something like it, and uploaded to some
cache server. Building and uploading this packaged cache file is slow (Rust is also notorious for 
producing enormous build output, sometimes into the gigabytes), so we'd like to avoid doing that if
we don't need to.

The simplicity of this system is the problem, though - every build will produce at least one new or
changed file in the output. For libraries, this is the new crate file, metadata about the
compilation, probably new test or benchmark executables. For binaries it will be the new
executable. In any case, this means that the cache system will waste time packaging and uploading
gigabytes of compiled objects on _every build_. Most of the time it will write _new_ files, too.
The new cache will include all of the previously cached build artifacts and more, meaning that the
caches tend to grow endlessly - making the build slower and slower - until the repository
maintainer manually deletes the caches and resets the clock.

## The Solution

Just delete those files before building the cache. That's basically it; add a `before_cache` step
that deletes the files that shouldn't be cached. It can be a bit tricky to figure out which ones
those are, though. Here's an annotated sample from Criterion.rs:

```
before_cache:
# Delete loose files in the debug directory
- find ./target/debug -maxdepth 1 -type f -delete
# Delete the test and benchmark executables. Finding these all might take some 
# experimentation.
- rm -rf ./target/debug/deps/criterion*
- rm -rf ./target/debug/deps/bench*
# Delete the associated metadata files for those executables
- rm -rf ./target/debug/.fingerprint/criterion*
- rm -rf ./target/debug/.fingerprint/bench*
# Note that all of the above need to be repeated for `release/` instead of 
# `debug/` if your build script builds artifacts in release mode.
# This is just more metadata
- rm -f  ./target/.rustc_info.json
# Also delete the saved benchmark data from the test benchmarks. If you
# have Criterion.rs benchmarks, you'll probably want to do this as well, or set
# the CRITERION_HOME environment variable to move that data out of the 
# `target/` directory.
- rm -rf ./target/criterion
# Also delete cargo's registry index. This is updated on every build, but it's
# way cheaper to re-download than the whole cache is.
- rm -rf ~/.cargo/registry/index/
```

You'll probably need to do some experimentation to figure out the right set of deletion commands
for your project. Travis-CI does (usually) helpfully log some of the files that changed to force a
re-cache. Most of the time your builds should say that nothing changed.

You will also probably want to disable Cargo's incremental compilation - it's not that useful for
a CI build and it adds more files that you'll have to delete. To do this, set the 
`CARGO_INCREMENTAL` environment variable to `0`.

Now, this doesn't entirely eliminate the problem of the cache files growing endlessly, since every
new version of your dependencies will add another file to the cache. It does enormously slow it
down though, and it means that you won't have to rebuild the cache on most build runs. Which in
turn means snappier CI builds for you and your contributors and warm fuzzy feelings for using
Travis-CI's infrastructure more efficiently.
