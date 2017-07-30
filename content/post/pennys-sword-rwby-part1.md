+++
date = "2017-04-25T13:31:36-06:00"
title = "Penny's Sword - RWBY - Part 1"
tags = ["RWBY", "Penny's Sword"]
categories = ["props"]
draft = true
description = ""
#TODO
images = [
]
+++

I started working on this last fall, but didn't have time to do much before
winter set in. RWBY is what originally got me into propmaking, so it's good to
get back to it. I've already made Yang's Ember Celica shotgauntlets and Adam's
#TODO: insert pics
Wilt & Blush Sword/Shotgun Combo. This time around, I'm going to be building one
of Penny's swords, which unfortunately don't have a cool name yet. This is the
first time I'm documenting my process, and I'm going to be experimenting with
a bunch of new tools and techniques this time (including electronics to make
it light up).

## Blueprints & Design

#TODO: Include something about the actual blueprints, maybe?

First, a quick overview of how I intend to build this. Hopefully at least some
parts of this plan will survive contact with reality. The plan is to make the
blade out of two pieces of 1/2 inch MDF laminated together around a steel rod.
The rod is mostly to have a secure place to attach the hilt and guard. The
light-up detail along the blade will be done with EL wire or LEDs covered by a
thin layer of scratched-up acrylic glass to diffuse the light. The other details
on the blade will mostly be made of wood, MDF and styrene. I'm not entirely sure
how I'm going to cut or sand the bevel for the edge of the blade, going to figure
that out when I get there. The guard is a more complex shape than it appears. It
isn't just a disk - the center is dished in a bit. I also need it to be hollow,
since that's where I'll put the batteries and electronics to make it light up.
Turning it on a lathe would be ideal, but I don't have a lathe or any idea how
to use one. I'll probably end up having to CNC that. The hilt will also be a
challenge - it's oval shaped, not round. I'm going to try to cut it out of a
wooden dowel with a spokeshave and make the extra details out of styrene. If
that doesn't work, I'll probably end up 3D printing, molding and casting it
instead.

## Blade

This is the part I did last fall. I took a big block of 1/2 inch MDF to my [local
makerspace](http://sktechworks.ca/) and put it on the CNC mill. I came up with
some plan to use the manual control mode of the mill to cut the block into two
halves of the blade, which I would then glue together. I milled a 1/4 inch round
groove down the center of the inside of the blade to hold a steel rod for
reinforcement. Then I flipped each piece over and milled a second groove on the
outside of the blade for the light-up section. Unfortunately, I've completely
forgotten the exact process I used to do this so I can't give more details.

Fast forward six months or so and it's time to glue this thing together. I
scuffed up the in-sides of the blade parts and the steel rod with sandpaper so
the glue would hold better and then covered it in wood glue and epoxy and clamped
the pieces together. This turned out to be a mistake. In my haste to get
everything together before the epoxy started to set, I didn't line up the two
parts properly. They're not even close.

#TODO: Insert shame pic(s)

D'oh. Shortly afterwards I also realized that the grooves I'd cut to hold the
acrylic light diffuser and EL wire are only 2-3mm deep - much too shallow to
contain both the 2mm acrylic sheet and the 2.6mm EL wire. Double D'oh. I decided
to attempt to repair the damage rather than just starting over. There's so much
to learn fixing mistakes, I thought, and anyway, if I really messed it up I
could still throw it out and start over.

I was able to deepen the groove for the light diffuser by placing a wide chisel
along the sides of the groove and tapping it lightly to cut the fibers and allow
the bits of MDF to come free without tearout. I then used a quarter-inch chisel
along the bottom of the groove to cut the bottom a bit deeper. I then proceeded
to cut another section out of the center of the groove using a ball-end bit on
my rotary tool for the EL wire to run along. That worked... less well, since it's
nigh-impossible to cut a straight line when the tool itself is pulling to one
side erratically. Fortunately, that part shouldn't be easily visible so it's OK.
I also used some Bondo to fill in the ends of the grooves so that they lined up
with each other.

I cut as much of the edge bevel on my scrollsaw as I could. Unfortunately, the
sword is too long to fit entirely on the saw, and the saw can't cut at the right
angles for much of the blade. If you look carefully, you'll notice that the
angle of the edge bevels isn't constant along the blade, and I can't do that on
my saw. In the end, I ended up cutting most of the edge bevel with a couple of
hand files and a rasp. That actually worked quite well. It took several hours and
a lot of elbow grease, but there's something satisfying about patiently working
with hand tools until something is just right. If you plan to do this at home,
be sure you know how about Draw Filing. If you don't, the idea is that you hold
one end of the file in each hand, press the center against the work and push
it forward and draw it back. I've found this technique to be much faster and
more controllable than filing along the length of the file using a sawing motion.

Once that was done, I spread some Bondo on some of the areas where I'd filed too
far and sealed the MDF with cyanoacrylate. I generally recommend thin CA for this,
as it soaks deeper into the MDF, but my bottle of thin CA is so old that it's
turned into thick CA all on its own. Have to get some more of that. Regardless
of the viscosity though, when the CA hardens you're left with a rough, but hard
and nicely sandable surface which won't soak up paint the way unsealed MDF does.
I suspect it would even be wet-sandable, but I've never tried that myself.

With that, plus some more sanding and spot-putty work, the blade is ready for
primer.

## Blade Details

## Guard

Oh boy. This thing gave me so much trouble. As I mentioned above, I don't have
a lathe and wouldn't know how to use one if I did. That means I really have two
options for making this piece. I could cut it on the CNC mill, or I could 3D
print it. I don't really like either one (as a computer programmer by day, both
of these options are too much like my real job) but needs must. I haven't had
much experience on the CNC mill at my local makerspace, and I'm proud to say
that I've added a number of shining new mistakes to that experience which I
hope to not repeat.

Because this part needs to be cut on both sides, I need to be able to flip over
the work piece without actually moving it relative to the bed of the CNC machine.
In my case, this means drilling a couple of holes through the material into the
sacrificial board on the bed of the machine, into which I can place pieces of
dowel. In theory, I can then flip the material over, make sure the dowels are
seated in their holes in the sacrificial board, and then carry on cutting on
the other side. In practice, the fact that I have to use standard drill bits
combined with the much higher RPMs of the router meant that this operation caused
nasty tearout. I can probably solve this by adding another piece of sacrificial
material on top of the workpiece.

Another problem is the fact that this CNC machine doesn't have any sort of
tool-changing device, so I have to manually change tools and adjust the zero
after every operation. That wouldn't be so much of a problem except it's easy to
accidentally reset the zero for the wrong axis part way through the process,
rendering it impossible to finish. Which is what I did the first time I tried
cutting the guard. The second time, my work piece came loose and I was informed
that I had the movement speed of the CNC router set far too high. Since this CNC
machine is someone's home-brew DIY project, it's somewhat lacking in documentation.
Fortunately nothing was damaged except my MDF.

This is about when I decided that maybe it'd be easier to just print it instead.

## Hilt
