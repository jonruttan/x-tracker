# Writing music

This guide is about the songs themselves: what a song file says, what
each part of it does to the sound, and how to put those parts together
into music.  The editor is one way to write them; a text editor is
another, and everything here can be typed by hand.  The songs are the
ones x-lang's `x/audio/tracker` plays, so a song written here plays in
x-roguelike as it plays in x-tracker.

`data/demo.xon` holds two finished songs: `lantern`, short and simple,
and `lighthouse`, which uses every effect there is.  The last section
takes `lighthouse` apart.  To hear either:

    x -l tracker -- data/demo.xon
    x -l tracker -- -s lighthouse play data/demo.xon

`data/hungarian-dance-5.xon` is a longer song, Brahms's Hungarian Dance
No. 5; the section after `lighthouse` says how it is made.

Every example below in an `xon` block is a whole file, and the spec
suite plays each one, so any of them can be copied into a file and
heard.

## A song file

A file holds `(wave ...)` forms and `(song ...)` forms, in any number.
A `;` starts a comment that runs to the end of the line.

```xon
; hum.xon -- the smallest song worth hearing
(song "hum" (bpm 100) (rows 4)
  (instrument tone (wave sine) (env (0 0) (10 60) (300 30)) (release 150))
  (pattern a
    (tone "C4 . E4 . G4 . E4 ."))
  (order a))
```

A song is made of:

- its name, a string;
- its timing: `(bpm N)`, `(rows N)`, `(ticks N)` and `(tension-bpm N)`;
- its song effects, such as `(reverb ...)`, over the whole mix;
- its instruments, `(instrument NAME PROP ...)`;
- its patterns, `(pattern NAME (INSTRUMENT "CELLS") ...)`;
- its order, `(order NAME ...)`, the patterns in the order they play.

A song needs an order and the patterns it names; everything else has a
default.  A song that names an instrument or a pattern it does not
define is refused, and a cell that is not a note, a hold or a let-go
is an error.  A form the tracker does not know is passed over without
a word, so a misspelt `(reverb ...)` is simply not heard.

## Time

    (bpm 96)          beats a minute; 90 when the song does not say
    (rows 4)          rows a beat; 4 when the song does not say
    (ticks 6)         ticks a row, for the cell effects; 6 when not said
    (tension-bpm 24)  beats a minute added at full tension; 0 when not said

A row lasts 60000 / (bpm x rows) milliseconds: at 96 bpm and 4 rows a
beat, 156 ms.  With 4 rows a beat, a row is a sixteenth note, four rows
a quarter and sixteen a bar of 4/4.  With 2 rows a beat a row is an
eighth note, and with 3 rows a beat the rows are triplets.

Ticks divide a row for the effects in a cell: an arpeggio steps once a
tick, a vibrato's period is counted in ticks, and a delay or a cut lands
on a tick.  At 96 bpm, 4 rows and 6 ticks, a tick is 26 ms.  More ticks
make the effects finer; fewer make them coarser and choppier.

Tension, from 0 to 100, is set by whatever plays the song: x-roguelike
raises it as danger nears, and the editor's `:tension N` sets it by
hand.  At tension T the song plays at bpm + tension-bpm x T / 100, so
`(bpm 96) (tension-bpm 24)` is 96 bpm when calm and 120 at full
tension.  The editor's `:pace N` plays the whole song at N percent of
its tempo, 10 to 400, without changing the file.

## Waves

A voice reads one cycle of a wave over and over at the pitch of its
note.  These waves are always there, the mixer's own:

- `sine`, the pure tone, which is also what an instrument with no
  `(wave ...)` plays;
- `square`, high for half the cycle and low for the other: hollow and
  loud, the chip-music lead;
- `triangle`, rising and falling in straight lines: soft, close to a
  sine with a little edge, the chip-music bass;
- `saw`, rising and dropping: every harmonic, the bright buzz of brass
  and strings; `inverse-saw` falls and leaps, and sounds the same on
  its own;
- `pulse`, the saw played at a width (below): a square at 50, thinner
  and more nasal as the width narrows;
- `noise`, a long table of random values, the stuff of drums;
- `metal`, a short run of noise that repeats, so it rings at the note's
  pitch: hats, bells, clanks.

The square, the saw and the pulse are drawn exact, so on high notes
their top harmonics fold back as tones of their own and they turn
rough; the triangle and the sine stay clean.  A `cut` tames the
brightness, though not the roughness.

### Pulse width

`(width (MS PCT) ...)` plays a voice's wave less itself PCT of a cycle
on.  On `pulse` (or `saw`) that is a pulse high for PCT of the cycle:
50 is the square, 25 thinner, 12 thin and buzzy.  The width moves over
the note like a bend, PCT at each MS, in straight lines between: a
width that moves is a pulse sweep, the classic chip-music shimmer.

```xon
(song "sweep" (bpm 100) (rows 4)
  (instrument chip (wave pulse) (width (0 12) (400 50) (800 12)) (env (0 0) (5 60) (800 40)) (release 100) (gain 40))
  (pattern a (chip "A3 . . . C4 . . . E4 . . . C4 . . ."))
  (order a))
```

### Ring and sync

`(ring CENTS)` and `(sync CENTS)` couple a voice to a second oscillator,
a modulator CENTS from the note's pitch, which follows the note but not
its bend.  A ring turns the wave over for half of each of the
modulator's cycles: on a `triangle`, a bell-like clang, the SID's ring
modulator.  A sync starts the wave again each time the modulator's
cycle ends, so its pitch is the modulator's and its harmonics are the
wave's own: a bend under a sync sweeps them, the tearing sync lead.

```xon
(song "sync" (bpm 100) (rows 4)
  (instrument lead (wave saw) (sync 0) (bend (0 0) (600 1900)) (env (0 0) (5 50) (600 40)) (release 100) (gain 30))
  (instrument bell (wave triangle) (ring 1900) (env (0 0) (2 60) (900 0)) (release 300) (gain 35))
  (pattern a (lead "A2 . . . . . . . C3 . . . . . . .") (bell "E5 . . . . . . . A4 . . . . . . ."))
  (order a))
```

On other waves a width reshapes their harmonics: at 50 the even ones
cancel and the odd ones stay, so a saw becomes a square and a triangle
stays a triangle.  A sine stays a sine at any width, quieter as the
width narrows.

### Waves of harmonics

Any other wave is made of harmonics and is defined in the file:

    (wave NAME AMP AMP ...)

Each number is the strength of one harmonic, the fundamental first,
then twice its frequency, three times, and so on.  The sum is scaled so
it never peaks louder than a sine, so only the proportions matter: `(1)`
is the sine, `(2)` the same.  The harmonics cannot all be 0.

    (wave soft 8 3 1)              a sine with a little body: bass, flute
    (wave hollow 6 0 2 0 1)        odd harmonics only: clarinet, square-ish
    (wave organ 6 0 3 0 2 0 1)     the same, brighter
    (wave reedy 6 4 3 2 1 1)       every harmonic, falling: reed, string
    (wave bright 12 6 4 3 2 2 1 1) close to a saw: buzzy leads
    (wave glass 5 0 0 2 0 0 0 1)   far harmonics: bells, glass, chimes

The odd harmonics give the hollow sound of a clarinet or a square wave;
all of them, falling off, give a saw's or a bowed string's buzz;
strong high harmonics with gaps between give bells and metal.  The
instrument's `cut` then decides how much of that brightness gets
through.

### Waves drawn by points

A wave can instead be drawn, as the points its one cycle passes
through, in straight lines between:

    (wave NAME (POSITION LEVEL) (POSITION LEVEL) ...)

Positions start at 0 and never go back; the last one is the end of the
cycle, so the scale is yours: `(0 ..) (1 ..) (2 ..)` cuts the cycle in
halves, `(0 ..) (8 ..)` in eighths.  Levels run from -100 to 100.  Two
points at the same position are a jump, and the end jumps back to the
start's level.

    (wave stair (0 100) (1 100) (1 0) (2 0) (2 -100) (3 -100))   three steps: a coarse, buzzy square
    (wave ramp (0 -100) (3 100) (4 -100))                        a saw leaning back: softer at the top
    (wave spike (0 0) (1 100) (2 0) (16 0))                      a short blip: thin and reedy

The mixer's own square, triangle and saws are drawn this way.  A shape
with sharp corners and jumps is bright; one of long, gentle slopes is
soft.

```xon
(wave stair (0 100) (1 100) (1 0) (2 0) (2 -100) (3 -100))

(song "stairs" (bpm 120) (rows 4)
  (instrument steps (wave stair) (cut 60) (env (0 0) (5 60) (300 30)) (release 120) (gain 40))
  (pattern a (steps "C3 . E3 . G3 . E3 . C3 . G2 . C3 . . ."))
  (order a))
```

A wave is named by an instrument as `(wave NAME)`.  A file can keep its
waves at its top, before its songs, so it needs no other file; one
whose waves are in another file is read with `-w FILE` (and `:waves
keep` in the editor copies them in).

```xon
(wave hollow 6 0 2 0 1)
(wave glass 5 0 0 2 0 0 0 1)

(song "two-waves" (bpm 100) (rows 4)
  (instrument reed (wave hollow) (cut 40) (env (0 0) (20 60) (400 40)) (release 200) (gain 40))
  (instrument bell (wave glass) (env (0 0) (3 40) (1200 0)) (release 600) (gain 30))
  (pattern a
    (reed "A3 . . . C4 . . . E4 . . . C4 . . .")
    (bell "E5 . . . . . . . A5 . . . . . . ."))
  (order a))
```

## Instruments

    (instrument NAME PROP ...)

The props are the voice's sound, and a few that only a song has:

    (wave NAME)          the wave; sine when not said
    (env (MS PCT) ...)   the envelope: the level, in percent, at each time
    (release MS)         how long a note takes to fade once let go; 200
    (cut PCT)            a low-pass filter, 1 to 100: 100 is open, low is dark
    (pan N)              -100 left to 100 right; 0 centre
    (gain PCT)           the instrument's level, in percent
    (detune CENTS)       the pitch moved by cents: 100 cents a semitone
    (note "C2")          a pitch of its own, whatever note starts it
    (hz N)               the same, in hertz
    (bend (MS CENTS) ...) the pitch's path from the note, CENTS at each MS
    (width (MS PCT) ...) a pulse's width at each MS (see Waves)
    (cutoff (MS HZ) ...) a resonant filter's cut-off at each MS, in hertz
    (res PCT)            that filter's resonance, 0 to 100
    (pass MODE ...)      what it lets through: low, band, high; low when not said
    (ring CENTS)         rung by a modulator CENTS from the note (see Waves)
    (sync CENTS)         hard-synced to a modulator CENTS from the note
    (at MS)              start this long after the note
    (layer calm)         heard less as the tension rises
    (layer tension)      heard more as the tension rises
    (voice PROP ...)     a voice of its own; any number of them

### The envelope

`(env (0 0) (10 80) (300 40))` rises from nothing to 80 percent in 10
ms, then falls to 40 percent by 300 ms, and holds 40 from then on, in
straight lines between the points.  An instrument with no envelope
sounds at full level from the start.

A note plays its envelope for as long as it is held, then falls to
nothing over the release.  A note let go before its envelope ends is
cut where it is, so the same instrument can play short and long notes:

- a pluck or a drum: a fast rise and a fall to 0, `(env (0 0) (2 90)
  (150 0))`; how long the note is held hardly matters;
- a held tone: a rise and a level it holds, `(env (0 0) (30 60) (400
  45))`, with a release to taste;
- a pad: a slow rise, `(env (0 0) (800 30) (3000 26))`, and a long
  release, so the chords swell in and blur into each other.

### Filter, pan and gain

`cut` is a low-pass filter, the instrument's brightness: `(cut 100)` is
the wave as it is, `(cut 30)` warm, `(cut 10)` muffled.  It matters
most on bright waves and on noise, where it is the difference between
a hiss and a rumble.

`cutoff` is a second filter after it, one that rings: the cut-off in
hertz, moving over the note like a bend, `res` how sharply it rings
there, and `pass` which side of it is heard, `low`, `band` or `high`, or
`low high` for a notch.  A low-pass swept up with a high `res` is the
classic synthesizer squelch; it is the filter of the C64's SID.

```xon
(song "squelch" (bpm 110) (rows 4)
  (instrument acid (wave saw) (cutoff (0 200) (150 2500) (400 300)) (res 80) (env (0 0) (5 60) (400 40)) (release 80) (gain 35))
  (pattern a (acid "A1 . A2 . A1 . C2 . A1 . E2 . A1 . G1 ."))
  (order a))
```

`pan` places the instrument; spread instruments apart to give each its
room.  `gain` sets its level against the others: a mix is mostly a
matter of gains.  Keep the total modest; a song of many instruments at
full gain clips.

### Drums: a pitch of their own

An instrument with `(note ...)` or `(hz ...)` keeps that pitch whatever
note is written in its cells: the note only starts it.  That is how a
drum is written, `C4` or any note in the cells, the drum's sound in the
instrument.  `bend` moves the pitch over the note, cents from it at
each time: a kick drum is a sine that starts high and drops.

```xon
(song "drums" (bpm 110) (rows 4)
  (instrument kick (wave sine) (note "C2") (env (0 0) (2 95) (140 0)) (bend (0 700) (45 0)) (release 30) (gain 70))
  (instrument hat (wave noise) (hz 1) (cut 85) (env (0 0) (1 30) (35 0)) (release 15) (gain 20) (pan 30))
  (pattern a
    (kick "C4 . . . . . C4 . C4 . . . . . . .")
    (hat  "C4 . C4 . C4 . C4 . C4 . C4 . C4 . C4 C4"))
  (order a))
```

### Voices

An instrument with `(voice PROP ...)` forms plays a voice for each, all
at once: each voice has its own props and the instrument's props under
them, its own winning.  Two voices detuned a few cents apart and panned
apart are the classic wide, beating sound of a pad or a string section;
a voice of noise and a voice of tone make a snare.

The envelope belongs to the instrument: every voice of a note follows
the instrument's `(env ...)`, or the first voice's when only the voices
have one.

```xon
(wave organ 6 0 3 0 2 0 1)

(song "voices" (bpm 80) (rows 4)
  (instrument pad (wave organ) (cut 22) (env (0 0) (600 30) (3000 26)) (release 1200) (gain 30)
    (voice (detune -7) (pan -55)) (voice (detune 7) (pan 55)))
  (instrument snare (env (0 0) (1 60) (30 25) (160 0)) (release 40) (gain 40)
    (voice (wave noise) (hz 1) (cut 55)) (voice (wave sine) (note "G3") (gain 50)))
  (pattern a
    (pad   "A3 . . . . . . . F3 . . . . . . .")
    (pad   "E4 . . . . . . . C4 . . . . . . .")
    (snare ". . . . C4 . . . . . . . C4 . . ."))
  (order a))
```

## Patterns and cells

    (pattern NAME
      (INSTRUMENT "CELLS")
      ...)

A pattern is a block of rows.  Each `(INSTRUMENT "CELLS")` is a channel,
a column of the pattern played by that instrument, one note at a time.
An instrument can have as many channels as it needs: the two `pad`
channels above are a two-note chord.  A pattern lasts as many rows as
its longest channel.

The cells are a row each, apart by spaces; any number of spaces, so
they can be lined up.  A cell is one of:

    C4        a note: a letter A to G, then # or b if any, then the octave 0 to 9
    C4:60     a note at 60 percent of the instrument's gain
    .         a hold: whatever the channel is playing carries on
    -         let go: the note sounding fades over its release

A note sounds until the next cell in its channel that is not `.`, or the
channel's end, and then fades over its release.  So `"C4 . . ."` is one
note four rows long, `"C4 C4 C4 C4"` four notes of a row each, and
`"C4 - . ."` a note of one row and three rows of silence after it.
`C4` is middle C, `A4` the A of 440 hertz; `F#3` and `Gb3` are the same
note.

Any cell can carry effects, each a `/`, a letter and its numbers:
`C4/v20,6` is a C4 with a vibrato, `C4:60/v20,6/f30` one at 60 percent
with a vibrato and a fade.

## The cell effects

A note's effects are its own cell's and those of the `.` cells it is
held over, each starting at its own row: `"C4 . ./v20,6 ."` is a plain
note that starts to waver on its third row.  Times are counted in
ticks, a row over the song's `(ticks N)`.  An effect lasts until the
next of its letter in the same note, or the note's end.

### a: arpeggio

`aX,Y,...` plays the note, then the note X semitones up, then Y up, and
so on, a tick each, round and round.  It turns one note into a chord
played so fast it sounds like one tone with a shimmer, the sound of old
computer music.  `a4,7` is a major chord, `a3,7` a minor one, `a12` an
octave trill.

```xon
(song "arpeggio" (bpm 100) (rows 4) (ticks 6)
  (instrument chip (wave sine) (env (0 0) (5 50) (600 30)) (release 100) (gain 40))
  (pattern a
    (chip "A3/a3,7 . . . F3/a4,7 . . . C4/a4,7 . . . G3/a4,7,12 . . ."))
  (order a))
```

### v: vibrato

`vD,P` wavers the pitch D cents either way, once every P ticks.  Both
numbers are needed.  A small, slow vibrato, `v15,8`, warms a held note;
a wide, fast one, `v50,2`, is a siren.  Put it on a `.` a row or two
into a note, as a singer would.

```xon
(song "vibrato" (bpm 90) (rows 4) (ticks 6)
  (instrument flute (wave sine) (env (0 0) (40 60) (500 50)) (release 200) (gain 40))
  (pattern a
    (flute "E5 . ./v15,6 . . . . . C5/v40,3 . . . . . . -"))
  (order a))
```

### s: slide

`sC` slides the pitch C cents, reached by the next slide or the note's
end, and held there.  `s-200` falls a whole tone, `s1200` rises an
octave.  Slides add up: `"C4/s200 . ./s200 ."` rises a tone, then
another.

```xon
(song "slide" (bpm 90) (rows 4) (ticks 6)
  (instrument bass (wave sine) (env (0 0) (6 80) (600 50)) (release 120) (gain 50))
  (pattern a
    (bass "G2 . . . G2/s1200 . . . C3 . ./s-200 . . . . -"))
  (order a))
```

### p: portamento

`pN` glides into the note from the channel's last note over N ticks.
The last note is the one before it in the same channel, even across
patterns; the first note a channel plays has nothing to glide from.  A
short glide, `p2`, is a bass player's slur; a long one, `p12`, a
synthesizer's swoop.

```xon
(song "portamento" (bpm 100) (rows 4) (ticks 6)
  (instrument lead (wave sine) (env (0 0) (10 60) (400 45)) (release 150) (gain 40))
  (pattern a
    (lead "C4 . . . G4/p3 . . . E4/p12 . . . C5/p2 . . -"))
  (order a))
```

### t: tremolo

`tD,P` dips the level D percent and back, once every P ticks.  Both
numbers are needed.  `t40,4` on a held note is a string section's
trembling; `t90,2` a hard, choppy pulse.

```xon
(wave reedy 6 4 3 2 1 1)

(song "tremolo" (bpm 90) (rows 4) (ticks 6)
  (instrument strings (wave reedy) (cut 30) (env (0 0) (80 50) (1000 40)) (release 300) (gain 40))
  (pattern a
    (strings "A3/t40,4 . . . . . . . E3/t90,2 . . . . . . -"))
  (order a))
```

### f: fade

`fP` takes the level to P percent, reached by the next fade or the
note's end.  `f0` fades a note out; on a `.` cell partway through, the
note holds and then fades.  It is how a long chord dies away at the end
of a song.

```xon
(song "fade" (bpm 90) (rows 4) (ticks 6)
  (instrument organ (wave sine) (env (0 0) (100 50)) (release 300) (gain 40))
  (pattern a
    (organ "C4 . . . ./f0 . . . E4/f20 . . . . . . -"))
  (order a))
```

### l: low-pass

`lP` closes the instrument's filter to P percent of its `cut`, reached
by the next `l` or the note's end.  A note that starts bright and darkens
as it sounds is a plucked string or a synthesizer's filter sweep.

```xon
(wave bright 12 6 4 3 2 2 1 1)

(song "low-pass" (bpm 90) (rows 4) (ticks 6)
  (instrument synth (wave bright) (cut 70) (env (0 0) (5 50) (800 40)) (release 200) (gain 30))
  (pattern a
    (synth "A2/l10 . . . . . . . C3 . . ./l15 . . . -"))
  (order a))
```

### w: width

`wP` moves a pulse's width to P percent of its cycle, reached by the
next `w` or the note's end, from the instrument's own width (50 for a
pulse that names none).  Two on one cell set it at once and then move
it: `C4/w10/w50` starts thin and opens over the row.

```xon
(song "width" (bpm 100) (rows 4) (ticks 6)
  (instrument chip (wave pulse) (env (0 0) (5 60) (800 40)) (release 100) (gain 35))
  (pattern a
    (chip "A3/w10 . . ./w50 C4 . ./w12 . E4/w40 . . . A3/w8 . . ./w50"))
  (order a))
```

### o: cut-off

`oH` moves the resonant filter's cut-off to H hertz, reached by the next
`o` or the note's end, from the instrument's own `cutoff`.  An
instrument with no `cutoff` has no resonant filter, and `o` does nothing.

```xon
(song "cut-off" (bpm 110) (rows 4) (ticks 6)
  (instrument acid (wave saw) (cutoff (0 400)) (res 75) (env (0 0) (5 60) (800 40)) (release 80) (gain 30))
  (pattern a
    (acid "A1/o3000 . A2 ./o300 A1/o2000 . C2 ./o500 A1/o4000 . E2 . A1 ./o200 G1 ."))
  (order a))
```

### x: ring, y: sync

`xC` rings the note with a modulator C cents from its pitch, and `yC`
hard-syncs it to one, as an instrument's `(ring C)` and `(sync C)` do,
the cell's taking the place of the instrument's for that note.  A note
takes the first of each on its rows.

```xon
(song "coupled" (bpm 100) (rows 4) (ticks 6)
  (instrument tri (wave triangle) (env (0 0) (2 60) (500 30)) (release 150) (gain 35))
  (pattern a
    (tri "C4 . . . C4/x700 . . . C4/x1900 . . . C4/y-500 . . ."))
  (order a))
```

### c: cut

`cN` lets the note go N ticks into the row it is on.  On a note's own
cell it shortens the note to less than a row, a staccato: `C4/c2` is a
stab a third of a row long at 6 ticks.  On a `.` cell it ends the note
partway through that row.

```xon
(song "cut" (bpm 100) (rows 4) (ticks 6)
  (instrument bass (wave sine) (env (0 0) (5 80) (400 60)) (release 40) (gain 50))
  (pattern a
    (bass "A1 . A2/c2 A1 . . E2/c3 . F1 . F2/c2 F1 . ./c3 C2 ."))
  (order a))
```

### d: delay

`dN` starts the note N ticks into its row.  It only works on the note's
own cell.  Delayed offbeats give a swing; a delay of a tick or two on
one note of a chord makes it strummed; a delay on a drum makes a flam.

```xon
(song "delay" (bpm 100) (rows 4) (ticks 6)
  (instrument hat (wave noise) (hz 1) (cut 85) (env (0 0) (1 30) (35 0)) (release 15) (gain 25))
  (instrument pluck (wave sine) (env (0 0) (3 50) (400 0)) (release 100) (gain 30))
  (pattern a
    (hat   "C4 . C4/d3 . C4 . C4/d3 . C4 . C4/d3 . C4 . C4/d3 .")
    (pluck "C4 . . . . . . . . . . . . . . .")
    (pluck "E4/d1 . . . . . . . . . . . . . . .")
    (pluck "G4/d2 . . . . . . . . . . . . . . ."))
  (order a))
```

### r: retrigger

`rN` starts the note again every N ticks for as long as it is held.  On
a drum it is a roll: `C4/r3` twice a row at 6 ticks, `C4/r1` six times.
On a pitched note it is a stutter.

```xon
(song "retrigger" (bpm 100) (rows 4) (ticks 6)
  (instrument snare (env (0 0) (1 60) (30 25) (160 0)) (release 40) (gain 40)
    (voice (wave noise) (hz 1) (cut 55)) (voice (wave sine) (note "G3") (gain 50)))
  (pattern a
    (snare ". . . . C4 . . . C4/r3 . . . C4/r2 . C4/r1 ."))
  (order a))
```

## The order

`(order intro verse verse chorus verse chorus outro)` plays the patterns
in that order, a pattern as many times as it is named.  Played in the
editor or in a game, the song goes round to the start of the order when
it ends; `play` without `--loop` plays it once.  Patterns can be of any
length; each plays its own rows before the next starts.

## Layers and tension

An instrument with `(layer calm)` plays at 100 - T percent of its gain
at tension T, and one with `(layer tension)` at T percent; one with no
layer is always at its own gain.  A note is not played at all when its
layer gives it 0.  So a song carries two arrangements of itself: as the
tension rises, the calm one fades out and the tense one in, and the
tempo rises by `tension-bpm` with it.

In a game the tension follows what is happening; in the editor, try
`:tension 0`, `:tension 50` and `:tension 100` while the song plays.
Write the instruments both layers share with no layer: the bass and the
melody usually.  Give the calm layer the soft, held parts, a pad or a
drone; give the tension layer what drives, a pulse, a fast hat, a
tremolo, a high bell.

```xon
(wave organ 6 0 3 0 2 0 1)
(wave reedy 6 4 3 2 1 1)

(song "layers" (bpm 90) (rows 4) (tension-bpm 30)
  (instrument bass (wave sine) (env (0 0) (6 80) (600 50)) (release 120) (gain 45))
  (instrument pad (layer calm) (wave organ) (cut 20) (env (0 0) (600 30) (3000 26)) (release 1200) (gain 30))
  (instrument pulse (layer tension) (wave reedy) (cut 30) (env (0 0) (4 60) (120 0)) (release 40) (gain 30))
  (pattern a
    (bass  "A1 . . . . . . . F1 . . . . . . .")
    (pad   "A3 . . . . . . . F3 . . . . . . .")
    (pulse "A2 A2 A3 A2 A2 A2 A3 A2 F2 F2 F3 F2 F2 F2 F3 F2"))
  (order a))
```

## The song effects

Song effects work on the whole mix, after the instruments, each over
what the ones before it made, in the order they are written.  A song
can have any number of them, the same kind more than once.

    (echo MS FB WET)
        The mix again MS later, FB percent of it fed back for more
        repeats, WET percent heard.  Each repeat is duller than the last.
        An echo a whole number of rows long stays in time: at 96 bpm and
        4 rows, a row is 156 ms, so (echo 312 30 16) repeats two rows on.

    (reverb SIZE DECAY WET)
        A room: SIZE percent of a middling room, DECAY percent fed back
        (up to 98: the higher, the longer it rings), WET percent heard.
        A little reverb, (reverb 90 70 20), puts the song in a space.

    (phase LEAST-MS MOST-MS PERIOD-MS FB WET)
        A short delay swept from LEAST-MS to MOST-MS and back every
        PERIOD-MS, FB percent fed back (-95 to 95) and WET percent heard
        (-100 to 100).  At a millisecond or two it is a phaser's swirl,
        at more a flanger's jet.

    (chorus VOICES MS DEPTH-MS PERIOD-MS WET)
        VOICES copies of the mix, 1 to 4, each delayed MS and swept
        DEPTH-MS either way every PERIOD-MS, WET percent heard.  It
        thickens and widens, as if more players were playing.

    (drive GAIN WET)
        The mix taken to GAIN percent of its level and rounded off: a
        quiet sound as it was, a loud one saturated.  WET percent of the
        change is kept.  Warmth at a little, distortion at a lot.

    (crush BITS HZ)
        Each sample kept to BITS of its 16 and held HZ times a second, 0
        for every frame: the grit of old hardware.  (crush 8 8000) is
        loud and plain; (crush 13 0) barely there.

    (sweep LOW-HZ HIGH-HZ PERIOD-MS RES)
        A resonant low-pass swept from LOW-HZ up to HIGH-HZ and back
        every PERIOD-MS, RES 0 to 100 its resonance: an auto-wah.  The
        player runs at 44100 frames a second, and the sweep goes no
        higher than a seventh of that, 6300 hertz.

    (limit CEILING RELEASE-MS)
        Keeps the mix under CEILING percent of full scale, turning it down
        at once when it would go over and back up over RELEASE-MS.  Put
        it last, as a safety against clipping.

A sensible order is the one a studio would use: what colours the sound
first (chorus, phase, drive, sweep, crush), then the space it is in
(echo, reverb), then the limit.  When a game changes from one song to
the next, an effect of the same kind in the same place carries on
ringing, so songs that share their effects change smoothly.

```xon
(song "effects" (bpm 96) (rows 4)
  (chorus 2 14 3 4000 25)
  (phase 1 3 6000 20 20)
  (drive 140 25)
  (sweep 800 5000 4000 30)
  (crush 12 22050)
  (echo 312 30 20)
  (reverb 110 72 20)
  (limit 92 120)
  (instrument tone (wave sine) (env (0 0) (5 60) (400 40)) (release 300) (gain 40))
  (pattern a
    (tone "A3 . C4 . E4 . A4 . E4 . C4 . A3 . . -"))
  (order a))
```

## Writing a song

### Drums from noise

Every drum is a short envelope on noise or on a falling sine:

- a kick: `(wave sine) (note "C2")`, a sharp attack and a fall to
  nothing in 100 to 200 ms, and a `bend` from 500 to 800 cents above
  down to 0 over the first 40 ms.  The drop is the thump.
- a snare: a voice of noise, `cut` 40 to 60, and a voice of sine at
  `G3` or so for its body, an envelope that falls fast then lingers a
  little, `(env (0 0) (1 60) (30 25) (160 0))`.
- a hat: noise with `cut` 80 or more and a fall in 30 to 50 ms; an
  open hat falls over 200 or so.
- a shaker or a tick: noise, a very short envelope, a low gain.

Noise is played at `(hz 1)`, read slowly through its long table, so it
does not repeat.  The `cut` is the drum's colour: low for a thud, high
for a hiss.  Pan the hats a little to one side.

A beat in 4/4 at 4 rows a beat, sixteen rows a bar:

    (kick  "C4 .  .  .  .  .  C4 .  C4 .  .  .  .  .  .  .")
    (snare ".  .  .  .  C4 .  .  .  .  .  .  .  C4 .  .  .")
    (hat   "C4 .  C4 .  C4 .  C4 .  C4 .  C4 .  C4 .  C4 .")

Kicks on 1 and 3, snares on 2 and 4, hats on every eighth.  Move a kick
to an offbeat for a push; add `/d3` to the offbeat hats to swing them;
fill the end of every fourth bar with a roll, `C4/r3`, `C4/r2`,
`C4/r1`, to say a section is ending.

### Bass

A bass wants a round wave, `sine` or `(wave soft 8 3 1)`, a `cut` of 20
to 35 so it rumbles rather than buzzes, an envelope that strikes and
then holds lower, and a short release.  Write it in octave 1 or 2.
Play the root of each chord on the beat; between, an octave jump cut
short, `A2/c3`, gives it bounce, and a `p2` into the next root makes it
walk.  Keep it centred.

### Pads

A pad holds the harmony: a dark, smooth wave, `cut` around 20, a slow
attack and a long release, and two voices detuned a few cents and
panned apart.  Write a channel a chord note, in octaves 3 and 4, each
note held as long as its chord lasts.  Keep its gain low: a pad is felt
more than heard.

### Arpeggiated chords

A chord can be played one note after another instead of all at once.
Written out a row a note, `"A4 C5 E5 C5"`, it is a broken chord, a
harp's or a synthesizer's rolling line; a bright, short wave such as
`glass` with a quick fall suits it.  Squeezed into one note with `a`,
`A4/a3,7`, it is the fast shimmer of a chip-tune chord, one channel
doing the work of three.

### Melody

A lead wants a wave with some brightness, a `cut` that lets it through,
and a place a little off centre.  Two voices detuned by 3 to 5 cents
thicken it.  Leave rests (`-`) so it breathes, put a vibrato on its
long notes a row or two in, and slide or glide between notes where a
singer would.

### Building tension

Tension is built by adding: more instruments, faster notes, higher
notes, effects that move.

- In the song's layers: the calm layer holds and soothes, the tension
  layer pulses and trembles, and the tension decides which is heard.
- In the patterns: a fill that doubles the hats, rolls the snare and
  slides the bass up an octave, `G1/s1200`, leads into what comes next.
- In the effects: a tremolo that speeds up, `t40,4` then `t60,2`; a
  vibrato that widens; a retrigger that gets faster.
- Release it by taking things away: drop to just the pad and the bass,
  or to silence for a row, before the next section comes back in full.

### Song structure

Write a few patterns and repeat them in the order, rather than many
patterns played once: the ear likes to hear a thing again.  A common
shape:

    intro    the harmony alone, or a few instruments, setting the key
    verse    the main tune over the full beat
    turn     the same with a different chord, or an answer to the tune
    fill     the end of a section, a roll and a rise
    bridge   somewhere new: other chords, a change of feel
    outro    the tune going, the chords fading, f0 on the long notes

With patterns of a bar or two, an order of eight or ten makes a song of
twenty or thirty seconds before it goes round, enough that its going
round is not tiresome.  A game's music plays for a long time: let it
be calm, let the end of the order lead back into its start, and keep
the busiest parts for the tension layer.

## The demo: lighthouse

`lighthouse` in `data/demo.xon` puts all of this into one song, in A
minor at 96 bpm, its tempo rising to 120 at full tension.

- Its waves are kept in the file: `organ`, `reedy` and `soft` from
  `lantern`, and `bright` and `glass` of its own.
- Its drums are a kick (a bent sine), a snare of two voices (noise and
  a sine), and a hat of noise.  The hats swing with `d3`, the intro's
  last hat rolls with `r2`, and the fill rolls the snare faster and
  faster with `r3`, `r2` and `r1`.
- The bass bounces on octaves cut short with `c3` and `c2`, glides
  with `p2`, slides up an octave into the bridge with `s1200`, and
  closes its filter on the last note with `l30`.
- The lead has two detuned voices; it wavers with `v20,6` on its long
  notes, some put on a `.` cell partway through, glides down to G#4
  with `p4` in the bridge, and fades with `f0` at the end.
- The arp plays broken chords in the intro and the outro, a written
  arpeggio, and chords squeezed into one note with `a3,7`, `a4,7` and
  `a4,7,12` in the fill and the bridge.  Its last note is at 70 percent
  and fades to 30.
- The pad is the calm layer, two detuned voices panned apart, and its
  three channels fade out with `f0` in the outro, one of them at 80
  percent.  The strings and the bell are the tension layer: the
  strings tremble with `t40,4`, faster with `t60,2` in the fill.
- Its effects run in the order above: chorus, phase, drive, sweep,
  crush, an echo two rows long, a reverb and a limit.
- Its order is intro, verse, turn, verse, fill, bridge, verse, turn,
  outro: six patterns, nine places.

Play it at `:tension 0` and at `:tension 100` to hear the two layers
trade places.

## The demo: hungarian-dance-5

`data/hungarian-dance-5.xon` is Brahms's Hungarian Dance No. 5 in G
minor, its notes from Albert Parlow's orchestration (Simrock, 1876).
It is a piece with sudden changes of tempo, and a song has one: the
changes are written into the rows instead.

- The song runs at 200 bpm, 4 rows a beat.  The Allegro gives a
  sixteenth 2 rows, a bar of 2/4 16 rows; the Vivace gives an eighth 2
  rows, a bar 8, so it is twice as fast with no change of bpm.  A poco
  rit. gives a sixteenth 3 rows, and the Vivace's ritardandos an eighth
  3 rows and then 4, slowing over two bars before snapping back.  A
  pattern's rows need not be the same in every bar.
- Its harmonic waves are kept in the file: `fiddle`, close to a saw,
  for the violins; `horn`, `soft` and `cimbalom`.  They are
  band-limited, where the mixer's `saw` and `square` fold back on the
  lead's high notes.  The flute is the mixer's `triangle` and the
  triangle its `metal`, a short loop of noise that rings at its note.
- The lead is the first violins, two detuned voices.  It slides up into
  the theme with `p2`, wavers on its long notes with `v15,7` and `v20,6`
  put on a `.` cell partway through, plays the second strain's repeated
  notes short with `c3`, trembles with `t20,4`, swells from 50 percent
  with `f100` in the Vivace's slow bars and fades with `f50` and `f40`.
- The horns are the offbeat chords, two channels, each note a row long
  and let go.  The bass is the cellos and basses on the beat.
- The cimbalom, the Hungarian hammered dulcimer, is not in Parlow's
  score.  Two voices make it: the `cimbalom` wave, and a `pulse` at 30
  percent of its gain whose `(width (0 25) (300 45))` sweeps from 25 to
  45 percent of a cycle, the changing ring of a struck string.  In the
  Vivace it plays the chords broken, a note at a time, its offbeat
  notes at 70 percent; it darkens the fast bars' downbeats with `l40`
  and rolls the slow bars' D7 with `r4`.  It closes the dance with an
  arpeggio, `a3,7,12`.
- The timpani roll with `r1` at the cadences; the triangle comes in
  where Parlow wrote it, the second time through the Vivace, one stroke
  a bar or a beat, low-passed so it rings and does not hiss.  The last
  chord is strummed with `d1` and `d2`.
- The flute is the tension layer, doubling the lead, an octave up in the
  theme's second time and in the Vivace; at full tension the dance is 40
  bpm faster.
- Its effects are a chorus, for a section of strings, a reverb, for a
  hall, and a limit.
- Its order is the score's form with its repeats: the theme, the second
  strain twice, the Vivace twice and its slow bars twice, then the theme
  and the strain again, and the coda.
