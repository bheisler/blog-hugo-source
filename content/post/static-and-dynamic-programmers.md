+++
description = ""
draft = true
categories = [""]
tags = ["", ""]
+++

_Epistemic Status: Pure conjecture, but I hope it's informed conjecture._

In theory, I'm on vacation at the moment with my whole extended family - parents,
siblings, neices and nephews. Waterparks are not really my jam, though, so I
figured I'd take the chance to do some reading. I picked up _A Philosophy of
Software Design_ by John Osterhout (which is excellent, by the way) and it
reminded me of some thoughts I've had about the long-running conversation
regarding static vs dynamic type systems. Specifically, I think that's the
wrong question, and I'll try to articulate why.

Conjecture: Some programmers find it natural to think in terms of types, while
some find this restrictive. The commonly-accepted pros and cons of static and
dynamic type systems are better understood as strengths and weaknesses of
static- and dynamic-aligned programmers, rather than attributes of programming
languages.

I've always been very strongly static-aligned, so my exploration of this idea
will be colored by that perspective. My history as a programmer starts with
some teenage experimentation with C++. My side-project programming started in
Java, briefly experimented with Scala, and is now exclusively done in Rust. I
learned Java at university and used it extensively at my first job, where I
stayed for seven years. After that, I moved to a Python shop and have been
there for two years, giving me some experience with dynamic languages, though
admittedly not as much.

One of the things I've noticed in my professional Python work is that I write
Python as though I wish I were writing Java - classes with a public interface
and private implementation details, where the class enforces (or merely
documents but doesn't assert) type invariants. My APIs often expect parameters
to be of a specific type (even if they don't use `isinstance` to check),
and I often feel as though adding documentation for parameters or return values
is redundant because the type hints tell you everything you need to know. I
like to think that my Java-style Python is good code (I have had co-workers
compliment me on my clean style) but I suspect it differs from what a skilled
dynamic-aligned programmer would produce.

It is commonly claimed that the dynamic-ness of dynamic languages makes them
easy to change and therefore good for rapid prototyping but the lack of guard
rails makes dynamically-typed projects harder to maintain over time. Conversely,
statically-typed languages are a drag on rapid iteration, but prevent enough
mistakes over time that they make long maintenance easier.

I think this is not correct. Rather, if I wanted to prototype something quickly,
I'd reach for Rust - the strictest, most pedantic language in my toolkit.
Crucially, I do not claim that this is the right choice for all programmers. My
programming habits (as well as all of the mental and technical tools that I use
to write code quickly) rely on static typing. I think in terms of types, so I
code in types, and so in my hands Python simply becomes a worse version of
Java. Conversely, a hypothetical Ruby or Javascript programmer who is more used
to thinking without static types might well find them burdensome, and the
compiler or interpreter errors that come with them to be a drag on iteration.

So that's why I think arguing over whether static or dynamic typing produces
better programs is asking the wrong question. It's like arguing whether French
or Chinese cuisine produces better food.

I should include some caveats here. First, there are lots of reasons why a
static-aligned programmer would be using a dynamic language. Most obviously,
they work at a job that requires it for one reason or another. Additionally,
for a lot of domains, there aren't a lot of great options for one side or
another. Web programming was and is dominated by dynamically-typed Javascript,
though this is slowly starting to change with the advent of languages like
Typescript and Elm. Typescript in particular is a good example of taking a
dynamically-typed language and changing it just enough to satisfy
static-aligned developers without alienating dynamic-aligned developers too
much, while Elm goes fully static. On the other hand, high-performance
programming, such as operating systems and video game engines, was dominated by
statically-typed C++ and more recently by C# (also static).

I don't think this is a simple binary, either. It's almost certainly a
spectrum, at least. I'd guess at a bimodal distribution where most people are
either mostly-static or mostly-dynamic, with a preference for one but the
ability to do good work in the other when needed. That would imply there are a
few folks equally comfortable in both, and a few on the edges who can't stand
to work with the opposing style at all. There are other axes as well. For
example, the popularity of C is hard to explain in this model; its type system
is paper thin and trivially sidestepped so it's not well suited to building
static designs. At the same time, it lacks built-in support for things like
dynamic dispatch that are necessary for good dynamic designs.

If I haven't made it clear by now, I don't think that static-aligned
programmers are better or worse than dynamic-aligned ones. I also don't think
that static-aligned programmers will necessarily write bad code in dynamic
languages or vice versa, though they likely will experience some drag on
productivity due to not having access to the their usual mental and technical
tools - I know I can write and update my code in Java or Rust faster than I
can change my code in Python.

Recently, Stripe released a type-checker for Ruby called
[Sorbet](https://sorbet.org/). It proved to be somewhat controversial, with
reactions ranging from "Finally!" to "Why would anyone want that?". I suspect
that this difference of opinion stems from an un-acknowledged divide between
static-aligned and dynamic-aligned Ruby programmers - the former want tooling
to strengthen their beautiful static-typing-inspired designs, while the latter
would prefer to create their beautiful dynamically-typed designs unimpeded.
More generally, this may be why gradual typing doesn't often work - adding
static type annotations to a well-designed dynamic codebase will just result in
a mess. It's really only useful if you have a static-aligned codebase in a
dynamic language. That happens more often than one might think, but not enough
to make gradual typing really take off.
