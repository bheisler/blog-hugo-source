+++
date = "2020-06-01T19:00:00-06:00"
description = ""
title = "Work-Efficiency vs. Step-Efficiency"
tags = ["GPGPU"]
categories = ["code"]
draft = true
+++

At work recently, I found myself trying to explain the Work-Efficiency vs Step-Efficiency tradeoff
to a coworker, but when I searched for online resources to help I couldn't find any that I liked,
so I decided to take a shot at writing my own. I found this idea presented in a video lecture
series on Youtube a while ago, but I have completely lost the link since I watched it. However,
it's just as applicable to any form of parallel processing, from SIMD instructions running on a
single CPU core up to massive clusters of thousands of computers. This is a short post explaining
this tradeoff and some of the implications.

== Work Efficiency vs Step Efficiency ==

To start with, lets define what those terms mean:

* Work Efficiency is the total amount of work that is done across one or more parallel workers to
  achieve some desired result.
* Step Efficiency is the critical path of _sequential_ work that must be completed to achieve some
  desired result.

The observation is that optimizations to improve step efficiency (eg. splitting one large task into
many smaller ones) nearly always worsen work efficiency (by increasing the total work done for the
same result, by adding coordination overhead, locking, etc.). Conversely, optimizations that 
improve work efficiency _sometimes_ worsen step efficiency. This is a more-specific version of the
general Throughput vs Latency tradeoff.

As an example, lets consider the problem of summing a large array of numbers.

The maximally work-efficient algorithm is a simple sequential sum - add the first and second
numbers, then add the sum to the third, and then the fourth, and so on until you reach the end of
the array. There's no way that we can further reduce the work here - we must read and add every
element to the sum, the overhead is as low as it could possibly be. However, this could still be
slow - the user must wait for one CPU core to grind through all N array elements by itself, which
means the wall-clock time could be long.

Another algorithm would be to add the first and second numbers together on one core, the third
and fourth on a second core, and so on, saving the results into a new array which is half the size
as the old. Then, we could repeat the reduction on the new array until ultimately we arrived at a
single sum. Of course, we could also give more than two elements to each core. This algorithm is
highly step-efficient - the wall-clock time is proportional to log2(N). However, the work efficiency
is reduced - the overall system now must start new threads, allocate an additional buffer, load
the array elements and write the temporary sums back into the buffer, etc.

Of course the same idea applies to much more complex problems. If you were working on an algorithm
to search for an optimum in a complex mathematical function, you might improve work efficiency by
having all the parallel processors stop periodically to share information (and thus narrow the
search space) at the cost of worsened step efficiency (because now you've added this sequential
sharing step that wasn't there previously).

An alternate way of thinking about step efficiency is - what would dominate the wall-clock time if
you had infinitely many parallel processors? In the real world of finite processors, Task 2 might
be blocked by Task 1 because it uses Task 1's output (a data dependency) or just because no
processor is available to execute Task 2 until Task 1 is done. If we had infinite processors though,
the second reason would never happen - there is always a processor available for a task - so the
wall-clock time would be determined by the data dependencies.

== So... what? ==

Well, for the most part I use this as a mental model or a way to describe the performance
characteristics of some code. It does have some practical implications though.

The right balance between step efficiency and work efficiency is affected by the number of parallel
processors available. As a rule of thumb, if you have far more parallel tasks than processors, it's
usually best to optimize for work efficiency even at the cost of step efficiency. On the other
hand, if you have far fewer tasks than processors, it's usually best to do the opposite.

To return to the summing-an-array example - the sequential sum would be a terrible fit for any
situation where more than one CPU core is available - even splitting the array into two parallel
tasks would save far more time than the small overhead incurred by the split. However, if we only
had one CPU core available (perhaps in an embedded device) then the two-by-two parallel reduction
method would be a much worse fit - the extra overhead from allocating buffers and context-switching
threads and so on would make it much slower than a simple sequential scan.

Earlier I said that improving step efficiency nearly always has a cost for work efficiency, but that
the reverse is only sometimes true. This isn't really a fundamental thing, it's just that in my
experience nearly all software is doing more work than is strictly necessary to accomplish its goal.
Most optimizations of most software just remove unnecessary work, and thus make the software
more work efficient with no cost in step-efficiency.