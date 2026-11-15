# Importing
@weight 2

tracker/midi, tracker/sid and tracker/import: a Standard MIDI File or a
C64 SID tune read into a song.  The files are made by the specs:
spec-midi takes a track as a list of (DELTA BYTE ...) events, spec-sid
a tune's 6502 code.

## MIDI

### a track's notes are cells: the note, its velocity as its gain, a let-go where it ends

```tracker
(def one (spec-midi 0 96 (list (list (list 0 255 81 3 7 161 32) (list 0 192 0)
                                     (list 0 144 60 127) (list 96 128 60 0) (list 0 144 64 64) (list 96 128 64 0)
                                     (list 0 144 67 100) (list 96 144 67 0)))))
(spec-lines (song-text (midi-song one "one" 4)))
```
---
```output
(song "one" (bpm 120) (rows 4) (ticks 6)
  (limit 90 120)
  (instrument piano (wave triangle) (cut 80) (env (0 0) (3 80) (300 50) (3000 0)) (release 300) (gain 31))
  (pattern p1
    (piano "C4    .     .     .     E4:50 .     .     .     G4:79 .     .     .     -"))
  (order p1))
```

### channels and programs are instruments, a chord takes a channel a note, and channel 10 is drums

```tracker
(def band (spec-midi 1 96 (list (list (list 0 255 81 3 7 161 32) (list 0 255 88 4 3 2 24 8))
                                (list (list 0 193 33) (list 0 177 7 127) (list 0 177 10 0)
                                      (list 0 145 48 100) (list 0 145 52 100) (list 0 145 55 100)
                                      (list 192 129 48 0) (list 0 129 52 0) (list 0 129 55 0))
                                (list (list 0 153 36 127) (list 0 153 42 90) (list 48 153 42 90) (list 48 153 38 110) (list 0 153 42 90)
                                      (list 48 153 42 90) (list 48 153 36 127)))))
(spec-lines (song-text (midi-song band "band" 4)))
```
---
```output
(song "band" (bpm 120) (rows 4) (ticks 6)
  (limit 90 120)
  (instrument bass (wave triangle) (cut 45) (env (0 0) (5 90) (400 60)) (release 100) (gain 50) (pan -100))
  (instrument kick (wave sine) (note "C2") (env (0 0) (2 95) (140 0)) (bend (0 700) (45 0)) (release 30) (gain 55))
  (instrument snare (env (0 0) (1 60) (30 25) (160 0)) (release 40) (voice (wave noise) (hz 1) (cut 55)) (voice (wave sine) (note "G3") (gain 50)) (gain 35))
  (instrument hat (wave noise) (hz 1) (cut 85) (env (0 0) (1 30) (35 0)) (release 15) (gain 19))
  (pattern p1
    (bass  "G3:79 .     .     .     .     .     .     .     -")
    (bass  "E3:79 .     .     .     .     .     .     .     -")
    (bass  "C3:79 .     .     .     .     .     .     .     -")
    (kick  "C4    .     .     .     .     .     .     .     C4")
    (snare ".     .     .     .     C4:87 .     .     .     .")
    (hat   "C4:71 .     C4:71 .     C4:71 .     C4:71 .     ."))
  (order p1))
```

### a change of tempo keeps its timing: the rows are of real time

```tracker
(def faster (spec-midi 0 96 (list (list (list 0 255 81 3 7 161 32)
                                        (list 0 144 60 100) (list 96 128 60 0)
                                        (list 0 255 81 3 3 208 144)
                                        (list 0 144 62 100) (list 48 128 62 0) (list 0 144 64 100) (list 48 128 64 0)))))
(write (song-patterns (midi-song faster "f" 4)))
```
---
    (("p1" ("piano" "C4:79" "." "." "." "D4:79" "E4:79" "-")))

### a note let go under the sustain pedal sounds until the pedal is up

```tracker
(def pedal (spec-midi 0 96 (list (list (list 0 176 64 127) (list 0 144 60 100) (list 24 128 60 0) (list 72 176 64 0)))))
(write (song-patterns (midi-song pedal "p" 4)))
```
---
    (("p1" ("piano" "C4:79" "." "." "." "-")))

### patterns are four bars, written once; a note held over a pattern's end is struck again

```tracker
(def bars (spec-midi 0 96 (list (list (list 0 255 88 4 1 2 24 8)
                                      (list 0 144 60 100) (list 480 128 60 0) (list 288 144 60 100) (list 480 128 60 0)))))
(def s (midi-song bars "b" 4))
(write (list (song-order s) (List map (fn (_ p) (pair (first p) (List map (fn (_ ch) (Str8 join " " (rest ch))) (rest p)))) (song-patterns s))))
```
---
    (("p1" "p2" "p1" "p3") (("p1" "C4:79 . . . . . . . . . . . . . . .") ("p2" "C4:79 . . . - . . . . . . . . . . .") ("p3" "C4:79 . . . -")))

### what is no MIDI file, of format 2, or of no notes is refused

```tracker
(def fails (fn (_ region) (guard (e (e msg)) (midi-song region "x" 4) "read")))
(write (list (fails (Bytes of-list (list 1 2 3)))
             (fails (spec-midi 2 96 (list (list (list 0 144 60 100)))))
             (fails (spec-midi 0 96 (list (list (list 0 192 5)))))
             (guard (e (e msg)) (import-song (Bytes of-list (list 80 75 3 4 0 0)) "x" 4 0 1))))
```
---
    ("x-tracker: not a MIDI file" "x-tracker: a MIDI file of format 2 is not imported; 0 and 1 are" "x-tracker: the MIDI file has no notes" "x-tracker: not a file import reads: a MIDI file (.mid) or a SID file (.sid)")

## SID

The tune is a program (spec-sid): its start sets the volume, a pulse
width of 50 and an envelope; each frame's call puts the next of 24
frames of a table on voice 1: C4 and E4 four frames on and two off, G4
B4 D5 a frame each, then C5 held.

### the 6502 adds and subtracts in decimal, shifts, tests bits, and runs the unofficial operations tunes use

```tracker
(def ran (sid-run (list 0xF8 0x18 0xA9 0x19 0x69 0x28 0xD8 0x85 0x10
                        0x38 0xA9 0x50 0xE9 0x70 0x85 0x11
                        0xA9 0x81 0x0A 0x2A 0x85 0x12
                        0xA9 0xC0 0x85 0x13 0x24 0x13 0x08 0x68 0x85 0x14
                        0xA7 0x12 0x60)
                  0x1000 0x1000))
(write (list (List take 3 ran) (List map (fn (_ a) (Vector ref a (List ref 3 ran))) (List range 16 21))))
```
---
    ((5 5 0) (71 224 5 192 240))

### a tune is run, a frame a tick and a row as many frames as its notes are apart

```tracker
(def tune-code
  (List append
    (list 0xA9 0x0F 0x8D 0x18 0xD4 0xA9 0x00 0x85 0xFB 0xA9 0x00 0x8D 0x02 0xD4 0xA9 0x08 0x8D 0x03 0xD4
          0xA9 0x09 0x8D 0x05 0xD4 0xA9 0xA5 0x8D 0x06 0xD4 0x60 0 0)
    (list 0xA6 0xFB 0xE0 0x18 0xB0 0x15 0xBD 0x40 0x10 0x8D 0x00 0xD4 0xBD 0x58 0x10 0x8D 0x01 0xD4
          0xBD 0x70 0x10 0x8D 0x04 0xD4 0xE6 0xFB 0x60 0x60 0 0 0 0)
    (List repeat 6 0x67) (List repeat 6 0xED) (list 0x13 0xDA 0x11 0x13 0xDA 0x11) (List repeat 6 0xCE)
    (List repeat 6 0x11) (List repeat 6 0x15) (list 0x1A 0x20 0x27 0x1A 0x20 0x27) (List repeat 6 0x22)
    (list 0x41 0x41 0x41 0x41 0x40 0x40 0x41 0x41 0x41 0x41 0x40 0x40) (List repeat 12 0x41)))
(spec-lines (song-text (sid-song (spec-sid "PSID" 0x1000 0x1000 0x1020 tune-code) "chip" 0 1)))
```
---
```output
(song "chip" (bpm 125) (rows 4) (ticks 6)
  (limit 90 120)
  (instrument pulse1 (wave pulse) (width (0 50)) (env (0 0) (2 100) (752 66)) (release 6) (gain 35))
  (pattern p1
    (pulse1 "C4/f76 E4/f76 G4/a4,7 ./a/s500 ./s0 .  .  .  ."))
  (order p1))
```


### a note's tail is held and faded to the level its release leaves, cut where the driver ends it, its arpeggio heard

Three notes, a frame's gate each, 13 and 14 frames apart as a driver
that runs a frame late now and then plays them: the first two have their
release ended by a quick one written six frames on, the third rings out
over an arpeggio.

```tracker
(def table (fn (_ f) (List map f (List range 0 40))))
(def note (fn (_ k) (match ((< k 13) 0x1167) ((< k 27) 0x15ED) ((= 0 (int% (- k 27) 2)) 0x1A13) (#t 0x22CE))))
(def tail-code
  (List append
    (list 0xA9 0x0F 0x8D 0x18 0xD4 0xA9 0x00 0x85 0xFB 0xA9 0x00 0x8D 0x02 0xD4 0xA9 0x08 0x8D 0x03 0xD4
          0xA9 0x09 0x8D 0x05 0xD4 0xA9 0xA5 0x8D 0x06 0xD4 0x60 0 0)
    (list 0xA6 0xFB 0xE0 40 0xB0 0x1B 0xBD 0x48 0x10 0x8D 0x00 0xD4 0xBD 0x70 0x10 0x8D 0x01 0xD4
          0xBD 0x98 0x10 0x8D 0x04 0xD4 0xBD 0xC0 0x10 0x8D 0x06 0xD4 0xE6 0xFB 0x60 0x60 0 0 0 0 0 0)
    (table (fn (_ k) (int% (note k) 256)))
    (table (fn (_ k) (int/ (note k) 256)))
    (table (fn (_ k) (if (List includes? k (list 0 13 27)) 0x21 0x20)))
    (table (fn (_ k) (if (if (< 5 k) (< k 13) #f) 0 (if (if (< 19 k) (< k 27) #f) 0 0xA5))))))
(spec-lines (song-text (sid-song (spec-sid "PSID" 0x1000 0x1000 0x1020 tail-code) "tail" 0 1)))
```
---
```output
(song "tail" (bpm 74) (rows 3) (ticks 14)
  (limit 90 120)
  (instrument saw1 (wave saw) (env (0 0) (2 100) (752 66)) (release 6) (gain 35))
  (pattern p1
    (saw1 "C4/f40/c6 E4/f28/c7 G4/f4/c9/a5 ."))
  (order p1))
```

### a tune with no frame's call has its interrupt's handler called, ended through the KERNAL's

```tracker
(def irq-code
  (List append
    (list 0xA9 0x20 0x8D 0x14 0x03 0xA9 0x10 0x8D 0x15 0x03 0xA9 0x0F 0x8D 0x18 0xD4 0x60) (List repeat 16 0)
    (list 0xA5 0xFB 0xD0 0x16 0xA9 0x67 0x8D 0x00 0xD4 0xA9 0x11 0x8D 0x01 0xD4 0xA9 0x09 0x8D 0x05 0xD4
          0xA9 0x11 0x8D 0x04 0xD4 0xE6 0xFB 0x4C 0x31 0xEA)))
(write (song-patterns (sid-song (spec-sid "RSID" 0x1000 0x1000 0 irq-code) "irq" 0 1)))
(write (song-instrument-text (sid-song (spec-sid "RSID" 0x1000 0x1000 0 irq-code) "irq" 0 1) "triangle1"))
```
---
    (("p1" ("triangle1" "C4" "." "." "." "." "." "." "." ".")))"(instrument triangle1 (wave triangle) (env (0 0) (2 100) (752 0)) (release 6) (gain 35))"

### what is no SID file, a tune it does not have, or one of no notes is refused

```tracker
(def fails (fn (_ region tune) (guard (e (e msg)) (sid-song region "x" tune 1) "read")))
(write (list (fails (Bytes of-list (list 80 83 73 68 0 2)) 0)
             (fails (spec-sid "PSID" 0x1000 0x1000 0x1000 (list 0x60)) 2)
             (fails (spec-sid "PSID" 0x1000 0x1000 0x1000 (list 0x60)) 0)))
```
---
    ("x-tracker: not a SID file" "x-tracker: the SID file's tunes are 1 to 1" "x-tracker: the SID tune plays no notes")

## the command line

### import adds the song to the file, named for the MIDI file; a second of its name is refused

```tracker
(def dir "/tmp")
(def mid (spec-write-bytes! (Str8 append dir "/x-tracker-spec-tune.mid")
           (spec-midi 0 96 (list (list (list 0 144 60 100) (list 96 128 60 0) (list 0 144 67 100) (list 96 128 67 0))))))
(def out (Str8 append dir "/x-tracker-spec-import.xon"))
(when (File exists? out) (File unlink out))
(write (list (tracker-main (list "import" mid "-o" out))
             (tracker-main (list "import" mid "-o" out))
             (tracker-main (list "import" mid "-o" out "-s" "again" "-r" "8"))
             (tracker-main (list "import" mid))
             (tracker-main (list "import" mid "-o" out "-r" "0"))
             (List map song-name (file-songs (file-read out)))
             (import-name "/a/b/tune.v2.mid")))
(File unlink out)
(File unlink mid)
```
---
```output
Imported x-tracker-spec-tune to /tmp/x-tracker-spec-import.xon: 0:01  1 patterns  1 in the order
Imported again to /tmp/x-tracker-spec-import.xon: 0:01  1 patterns  1 in the order
(0 1 0 2 2 ("x-tracker-spec-tune" "again") "tune.v2")
```
