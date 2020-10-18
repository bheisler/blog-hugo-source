+++
date = "2020-10-18T15:00:00-06:00"
description = ""
title = "Building a Recipe Manager - Part 2 - Druid Experience Report"
tags = ["Rust"]
categories = ["code"]
prev = "/post/recipe-manager-part-1/"
+++

It's been a couple of weeks since the [last post], and as promised I'm back with some progress on
the ingredient editor. The last post talked about my goals for this project, technical design
decisions based on those goals, and my philosophy on starting challenging projects. This post
is more of an experience report from my first few weeks of working with Druid.

[last post]: /post/recipe-manager-part-1/

Before we dig into Druid though, the progress in the last two weeks.

## The Current Ingredient Editor

![Prototype Ingredient Editor](ingredient-editor-v2.png)

I've done quite a bit of work on this so far. Compared to last week, probably the biggest thing is
that it now displays error messages to the user when they type something wrong.

As discussed last time, Druid's built-in [Parse] widget simply discards parse errors. It's not
possible to get that information out of the Parse widget so I had to write my own, which I creatively
named BetterParse. Druid upstream has since broken my BetterParse widget and I haven't figured out
how to fix it yet, but more on that later. Even when it works, my widget is a bit janky - I'd 
like to make it wait until the textbox loses focus before it displays an error, for instance - 
but it works pretty well.

[Parse]: https://docs.rs/druid/0.6.0/druid/widget/struct.Parse.html

As you can see next to the Carbs value, there's a placeholder on each text box that describes what
sort of data to fill in when the box is empty. This is something that Druid just has built-in
support for, so it's not too exciting from a development perspective, but it does help the user
understand how to use the GUI. That's important for a smooth user experience. Unfortunately,
in the revision of Druid that I'm using, textboxes sometimes get confused about the text styling
between real values and placeholders - here the placeholder is solid (like the other user-entered
values) when it should be faded. Sometimes textboxes also display the last thing you typed in them
as the placeholder - I've seen that with the textbox in the Aliases field.

Speaking of which, there's a totally new widget for adding aliases. They were taking up a lot of
vertical space and I figured they wouldn't need to be edited much, so I wrote a custom widget
that displays each alias in its own little bubble with a delete button. You can't see it in this
image but the bubbles are automatically wrapped to fit in the space allotted, which was
surprisingly tricky to implement. I plan to reuse this widget for defining tags on recipes for easy
searching later.

I've also added the Mass and Volume fields. These will later be used for automatic unit conversion.
See, I like to measure everything by mass when I'm cooking. It's more precise and consistent than
measuring things by volume and that appeals to my engineering brain, but that's not the main
reason. The biggest reason is that it's so much _cleaner_. I can just pop the bowl on the scale and
scoop or pour ingredients straight into the bowl - I don't have to dirty measuring cups or spoons.
Unfortunately, many recipes haven't gotten the memo on this and still list measurements in terms of
volume, which means I frequently need to pull out my phone, open [Frink] and do some quick math.
But hey, if I'm writing my own tooling I can just make it do the math for me. In order to do that,
it will need to know the density of each ingredient. I hope to be able to type in "Butter, 3 tbsp"
or "6 ounces" and have it instantly figure out the mass I need to measure out in grams - and also
the precise caloric and macronutrient content of that amount of butter, without me needing to
figure out exactly how many 'servings' of butter that represents.

[Frink]: https://frinklang.org/

The unit parsing is currently powered by the [uom] crate. It's not quite as human-friendly as I
want it to be - uom's parsing code will accept "1 g", but won't accept any of "1g" (no space), "1
gram", "1/2 lb", or "½ lb". All of these will certainly be needed for a good user experience. I've
built my own parsing layer on top of uom's which at least allows for missing spaces. I plan to
extend that to handle fractions as well, but uom doesn't provide any way to parse units from
strings that contain the full unit name (eg. "gram" or "grams", rather than "g"). I've filed a
feature request for that; I hope they can implement something for that soon.

[uom]: https://crates.io/crates/uom

Finally, the auto-save actually works, asynchronously writing the data out to a TOML file. It's
pretty janky right now and doesn't properly handle save errors, but it works on the happy path at
least.

## Druid Experience Report

If you're like me, you might have seen that Druid is officially unfinished and wondered "just how
unfinished is it, really?" Unfinished as in "not even usable yet", or unfinished as in 
"perfectionist obsessing over the last little bit of polish"?

After working with it so far, I'd say it's unfinished as in "usable for the serious early-adopters,
but still missing a lot of things that a production-quality GUI toolkit should have." Despite that,
I actually really like it so far, from my perspective as a serious early-adopter.

### What I like about it

I think I'd like to start with the praise. I'm actually pretty happy with Druid so far. It's fast
and light - even in debug builds, which is nice for development. I didn't expect a Rust GUI
framework to be as mature as the Java ones I'm more familiar with.

I think the thing I like most about Druid is the freedom it gives me to just write my own widgets
when the built-in ones are missing or insufficient. The underlying drawing primitives and
text-layout systems are great - they Just Work and do everything I've needed from them yet with
minimal trouble. It's really quite easy to write custom widgets that work in exactly the way you
want them to work - my custom alias-list widget above took me maybe 2-3 hours to develop from
scratch, including the time to write and debug my hacky code to flow aliases and the text box to
the next line when there isn't enough space.

This level of performance and fine control over the low-level details when you want it makes Druid
feel genuinely Rusty - just like it's been designed to work with the borrow-checker, it feels like
it's been designed with the same core values and design goals at Rust itself.

The way widgets compose together also feels very Rusty - to add parsing to a text box, you wrap it
in another widget. To add padding or custom behavior to a widget, you wrap it in different widgets
- just like how you wrap iterators or futures in other structures to modify their behavior. There
are a lot of helper functions to make this easy, and it all works quite well.

I hope that as it matures it will solve a lot of the problems that I discuss below. If the Druid
developers are listening, I think the in-window modals are probably #1 on my wishlist - I can work
around, roll my own, or just live with pretty much everything else, but I can't build an
auto-completing text box without that.

### Missing Features

As I mentioned above, the Parse widget gives the user no feedback at all if they type something that
can't be parsed. Since the Parse widget works with data in an `Option<T>` rather than a 
`Result<T, Err>`, there's no way for the application itself to extract the error message to display
it separately, either - the application can only tell that it was invalid at all if the Parse
widget sets the value to None rather than Some. This wouldn't fly at all in a production-quality
GUI toolkit, which is why I had to write my own BetterParse widget. I understand that the Druid
developers are aware of this problem and it's on the roadmap to be fixed someday, but I don't
want to wait for someday.

The existing widget containers are very primitive - there's no way to align objects on a grid, for
instance. Early adopters should get used to manually specifying insets, widget sizes, and the like,
though fortunately it _does_ provide the [Flex] type to help with positioning. Also, Druid only
supports a single size for each widget, rather than the min/desired/max sizes like JavaFX and
Swing. Among other things, that means that Druid cannot automatically compute a minimum size for
the window that would prevent widgets from running off the edge of the window or overlapping each
other. Thus, the rendering goes pretty wonky if the user shrinks the window too small, and if any
widget is added or changes size the window won't resize to accomodate. Although it was kinda fun to
implement my own reflowing logic for the alias list, I'm sure I got it wrong in a bunch of subtle
ways - it would be nice if Druid provided a container for this.

[Flex]: https://docs.rs/druid/0.6.0/druid/widget/struct.Flex.html

There are no modals of any kind yet, which means that combo-boxes, auto-completion lists, tooltips
and error dialogs are all completely absent. Worse, they can't be implemented by the application
developer either. This is a big problem for me, since I planned to have extensive autocomplete
support, especially for adding ingredients to recipes. For now I'm going to just let the user type
in their text and have the recipe manager automatically select the best match, rather than
displaying a list of the top 5-10 and letting the user select one.

A non-exhaustive list of other things I've found that are missing:

- There's no way to disable or grey-out widgets.
- Multi-line text-boxes are only just recently supported (in fact, that's the work which broke my
BetterParse widget, so I don't have it yet in my pinned revision of Druid). It's not in a published
version yet though.
- No tabs for switching back and forth between views; the user can probably approximate this using
  existing widgets though.
- No widget for a visually-distinct toolbar along the bottom. I rolled my own with a Flex and a
black border, but it's ugly and I'm going to need to replace it with something better eventually.
- No widget to visually separate different regions of a window into separate logical groupings.
- No Table widget for displaying tabular data, let alone sorting, filtering, or editing it.
- There doesn't seem to be any event when a window loses focus?

I don't mean any of this as a criticism of Druid's developers - I fully understand that it is a
phenomenal amount of work to build a production-quality GUI toolkit and I don't expect Druid to
provide everything that a fully-mature toolkit would at this early stage of development. However,
if you're considering using Druid for a project, you should expect to need to do a lot of the layout
by hand, write a lot of custom widgets, and in some cases you'll have to adapt your UI design
around things that Druid doesn't yet support.

### Unclear Design Guidance

Some UI toolkits are fully reactive - web frameworks tend to be like this, where the data model is
held separately and passed to a function that constructs and returns a widget graph. In these, user
actions cause the model to be updated and the widget-graph to be reconstructed (a process which is
typically optimized using a virtual DOM). Some UI toolkits are fully retained - the data model is
stored in (or at least directly attached to) a persistent widget graph. User input causes direct
changes in the widget graph that are reflected in the data model. This is how most object-oriented
GUI toolkits work, especially the Java ones that I'm quite familiar with from doing a lot of Java
GUI work at a previous employer.

Druid tries to be a hybrid of both approaches, and I'm not really convinced it's quite got all the
kinks worked out.

For example, when you open a Druid window, you give it the data model struct which will be used to
store the information for the GUI and a function to build a widget tree - like a reactive system.
But the data model is not passed to the function - instead you need to build and return a widget
tree in isolation, without looking at the data model. A system of lens objects is used to define
which widgets map to which fields, and this works reasonably well. These lenses are used to directly
modify the data model in response to user input, which then updates the existing widget tree - more
like a retained system.

But some GUI widgets need to have access to the data to define their contents. Any list of
widgets that grows as the user adds data, any widget that should only be visible under some
circumstances, etc. These widgets take a closure that generates their contents based on the data
they're loaded with. It works just fine, but it feels incongruous with the rest of the design.

On top of this, there are two different ways to communicate with a widget. Most widgets connect to
a field in the data model structure through lenses. I'm simplifying here, but you can think of a
Lens as a bi-directional function. To connect a textbox to a field in a structure, a Lens is
provided which can either retrieve the field from the structure or update the field in the structure
to match a new value. Most lenses are simple and automatically generated by a procedural macro,
but they can be quite powerful when written by hand. For instance, you can transform the model data
in pretty much arbitrary ways - my first attempt at the alias list used a custom lens to transform
each String into a custom struct that included the string itself and a boolean flag which indicated
whether that alias should be deleted. The delete button set the flag to true, and the lens simply
dropped 'deleted' aliases when it did the reverse transformation - the data model wouldn't contain
the deleted ones. Since the data model was updated, the GUI would then be updated again and
delete the widgets associated with the deleted value. It's sort of strange, but it works quite well
once you get used to it. This use of functional transforms feels like a reactive GUI approach.

The other system is Commands. These are basically programmer-defined events that are propagated
through the widget graph like keyboard and mouse events. They can also be sent to a specific widget.
This results in a sort of side-channel by which widgets can talk to each other. This would be much
more at-home in a retained-mode GUI system - in fact it's quite similar to the Events system in
JavaFX.

The main problem with this is that there's a lot of state in any GUI that isn't logically part of
the application model or the widget configuration, and it's not really clear where Druid wants you
to keep it. Consider my little auto-save timer - it needs somewhere to store which state it's in
(saved, failed, invalid or ticking) and how much time is left before the editor is auto-saved.
Where should that state live? It's not logically part of the application's data model, so it seems
strange to force the application developer to include an AutoSaveTimerState field in their model
structure. Should it be stored in the widget itself? But then outside code needs to send Commands
to the widget to tell it to start ticking or to notify it that data was saved successfully. Rather
than being a smooth hybrid of the retained and reactive GUI styles, Druid ends up forcing the
programmer to pick one style or the other on a case-by-case basis - and the design and
documentation give little guidance about which style should be used in which cases.

In some discussions on the Druid Zulip channel I was told that the lens style is more idiomatic,
but when I've used it it's always seemed to me to be more complex. In my code so far, I've kept all
of my state inside widgets except where it should naturally come from the application's data model,
with a small handful of Commands to keep things connected. Instead of writing custom lenses to
transform my data to suit the widgets, I'm only using the basic auto-generated lenses and writing
my custom widgets to contain all of their own state and complexity. It's been working well enough
for me so far.

### Other minor problems

As much as I like the Widget trait it is rather complex. There are five different functions with
different parameters that do different things, and it's not documented well enough to support that
complexity.

`Widget::event` and `Widget::lifecycle` seem redundant - why do the lifecycle events need to be
separate from the other events? Combining them could remove one fifth of the complexity of the
widget trait.

Druid has a WidgetPod structure which is used by containers to tell their children where they
should be positioned on the screen. There are a few things I don't like about this. Why can't
container widgets just lay out their children directly, without this wrapper? Further, for some
reason WidgetPod doesn't work with Druid's normal `Widget::update` function for updating its data.
Normal Druid widgets get a reference to the new state along with a reference to the old state for
comparison. When I was implementing a widget that contained a WidgetPod, I was surprised to
discover that it doesn't implement this interface - instead the caller provides the new data only.
WidgetPod apparently contains its own clone of the old data, even though the widget which owns it
must have been given the old-data reference. Neither the documentation nor source code makes it
clear why this design choice was made, and it's particularly annoying to me because it seems to be
a part of why my BetterParse widget is broken on newer versions of Druid. It must take up a good
deal of memory too, if every widget in a container is keeping its own redundant clone of the data
model. Even if there is a good reason why one would want to have this, this feels like two distinct
responsibilities lumped together into one structure - what if I want to have layout, but without the
old-data management?

## Conclusion

So, that's my report on my first few weeks' experience with Druid. It's usable, but very incomplete.
I'm optimistic about its future, though I am still trying to keep my GUI code decoupled from
the other code in case I need to replace it with something else later.

Because of Canadian Thanksgiving and tinkering with some other projects, I think I've probably
put in another 12-14 hours in the past two weeks to get the ingredient editor to its current state.
It's definitely going slower than it might be with another toolkit, but then I am taking a lot of
care to get things _just right_, where in JavaFX I'd probably just go with the built-in widgets
and not bother to customize things so much.

As I'm developing this code and writing this series, I find that I still have things to say, so
stay tuned for the next post next Sunday. Right now I'm thinking it will be about parsing user
input and how hard it is to do it right.
