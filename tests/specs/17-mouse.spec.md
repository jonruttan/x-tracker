# The mouse
@weight 2

Schism Tracker's mouse: a click picks what is under it, a drag marks a
block or moves an envelope's point or a loop's end, the wheel scrolls;
the pages are a row of their names, each clicked to show it.

## reading it

### a terminal's reports of the mouse are read as Term decodes them

```tracker
(import x/core/doors char->int str-byte-ref)
(def keys-of
  (fn (_ text)
    (def bytes (List map (fn (_ i) (char->int (str-byte-ref text i))) (List range 0 (Str8 length text))))
    (def read (fn (_) (if (null? bytes) () ((fn (_ b) (set! bytes (rest bytes)) b) (first bytes)))))
    ((fn (self acc) ((fn (_ k) (if (null? k) (List reverse acc) (self (pair k acc)))) (keys-read read))) ())))
(write (keys-of "\x1b[<0;10;3M\x1b[<32;12;5M\x1b[<0;12;5m\x1b[<65;1;1M\x1b[<6;2;2M\x1b[1;2A"))
```
---
    (('mouse 'press 'left 2 9 ()) ('mouse 'drag 'left 4 11 ()) ('mouse 'release 'left 4 11 ()) ('mouse 'wheel 'down 0 0 ()) ('mouse 'press 'right 1 1 ('shift)) 'shift-up)

## the pattern

### a click moves the cursor to a cell's column, the heading to a channel; a drag marks a block; the wheel scrolls

```tracker
(def m (fn (_ a b r c . mods) (list 'mouse a b r c (if (null? mods) () (first mods)))))
(def st (edit-make (file-parse "(song \"t\" (instrument a (wave sine)) (instrument b (wave sine))\n  (pattern p (a \"C4 . . . . . . .\") (b \"C3 . . . . . . .\"))\n  (order p))") () ()))
(def screen (Screen make 20 100))
(spec-draw! st screen)
(spec-keys! st (list (m 'press 'left 6 30) (m 'release 'left 6 30)))
(def a (list (edit-place st) (Vector ref 31 st)))
(spec-keys! st (list (m 'press 'left 3 6)))
(def b (list (edit-place st) (Vector ref 31 st)))
(spec-keys! st (list (m 'press 'left 4 5) (m 'drag 'left 5 6) (m 'drag 'left 7 25) (m 'release 'left 7 25)))
(def c (list (edit-place st) (Vector ref 26 st) (edit-message st)))
(spec-keys! st (list (m 'press 'left 4 5)))
(def d (Vector ref 26 st))
(spec-keys! st (list (m 'press 'left 5 5 (list 'shift))))
(def e (list (Vector ref 26 st) (edit-place st)))
(spec-keys! st (list (m 'wheel 'down 6 10) (m 'wheel 'down 6 10)))
(write (list a b c d e (edit-place st)))
```
---
    ((("p" 2 1) 2) (("p" 2 0) 0) (("p" 3 1) (0 . 0) "Block: rows 0 to 3, channels 1 to 2   Alt-C copy  Alt-Z cut  Alt-P paste  Alt-Q Alt-A transpose  Alt-U unmark") () ((0 . 0) ("p" 1 0)) ("p" 7 0))

## the pages

### the row of pages shows each when clicked; a click picks a list's line, a second click is Enter; the order line goes to a place

```tracker
(def m (fn (_ a b r c) (list 'mouse a b r c ())))
(def st (edit-make (file-parse "(song \"t\" (instrument a (wave sine))\n  (pattern p (a \"C4\")) (pattern q (a \"D4\"))\n  (order p q))") () ()))
(def screen (Screen make 20 100))
(spec-draw! st screen)
(def bar (Str8 trim-right (Screen row-text screen 2)))
(spec-keys! st (list (m 'press 'left 2 60)))
(def a (Vector ref 30 st))
(spec-draw! st screen)
(spec-keys! st (list (m 'press 'left 6 4)))
(def b (Vector ref 25 st))
(spec-keys! st (list (m 'press 'left 6 4)))
(def c (list (Vector ref 30 st) (edit-place st)))
(spec-draw! st screen)
(spec-keys! st (list (m 'press 'left 1 8)))
(def d (edit-place st))
(spec-keys! st (list (m 'press 'left 2 23)))
(def e (Vector ref 30 st))
(spec-keys! st (list (m 'press 'left 2 60)))
(spec-draw! st screen)
(spec-keys! st (list (m 'wheel 'down 5 4)))
(write (list bar a b c d e (Vector ref 25 st)))
```
---
    (" F1 Help  F2 Pattern  F3 Samples  F4 Instruments  F5 Info  F11 Order  F12 Song" 'orders 1 ('pattern ("q" 0 0)) ("p" 0 0) 'samples 1)

### an envelope's point is dragged, one step of undo; a loop's ends are dragged on the sound

```tracker
(def m (fn (_ a b r c) (list 'mouse a b r c ())))
(def target (fn (_ st kind) (List find (fn (_ t) (eq? (first t) kind)) (Vector ref 43 st))))
(def dir (Str8 append ((fn (_ d) (if (null? d) "/tmp" d)) (Sys getenv "TMPDIR")) "/x-tracker-spec-mouse"))
(unless (File exists? dir) (File mkdir dir))
(sample-write! (first (sample-resample (first (Bytes of-hex "00000040ff7f0040000000c00180ffbf")) 8 2000 #t)) 2000 8000 (Str8 append dir "/s.wav"))
(def st (edit-make (file-parse "(wave kick (sample \"s.wav\"))\n(song \"t\" (instrument a (wave kick) (env (0 100) (100 50) (200 0)))\n  (pattern p (a \"C4\")) (order p))") (Str8 append dir "/t.xon") ()))
(def screen (Screen make 30 100))
(spec-keys! st (list 'f4))
(spec-draw! st screen)
(def e (target st 'envelope))
(def undos (List length (Vector ref 13 st)))
(spec-keys! st (list (m 'press 'left (+ (List ref 1 e) 3) (+ (List ref 3 e) 40)) (m 'drag 'left (List ref 1 e) (+ (List ref 3 e) 50))
                     (m 'drag 'left (List ref 1 e) (+ (List ref 3 e) 60)) (m 'release 'left (List ref 1 e) (+ (List ref 3 e) 60))))
(def a (list (song-instrument-text (edit-song st) "a") (- (List length (Vector ref 13 st)) undos) (Vector ref 35 st) (Vector ref 36 st)))
(spec-keys! st (list 'f3))
(spec-draw! st screen)
(def s (target st 'sound))
(spec-keys! st (list (m 'press 'left (List ref 1 s) (+ (List ref 3 s) 10)) (m 'drag 'left (List ref 1 s) (+ (List ref 3 s) 40))
                     (m 'release 'left (List ref 1 s) (+ (List ref 3 s) 40))))
(def b (List ref 2 (first (file-waves (edit-doc st)))))
(spec-keys! st (list (m 'press 'right (List ref 1 s) (+ (List ref 3 s) 70))))
(write (list a (List ref 4 s) b (List ref 2 (first (file-waves (edit-doc st))))))
```
---
    (("(instrument a (wave kick) (env (0 100) (184 100) (200 0)))" 1 1 #f) 99 ('sample "s.wav" 204 816) ('sample "s.wav" 204 1428))

### F1 on the row of pages opens the help, the wheel scrolls it and a click closes it; a click picks a song from :song's list

```tracker
(def m (fn (_ a b r c) (list 'mouse a b r c ())))
(def st (edit-make (file-parse "(song \"a\" (instrument a (wave sine)) (pattern p (a \"C4\") (a \"E4\")) (order p))\n(song \"b\" (instrument a (wave sine)) (pattern p (a \"C4\")) (order p))") () ()))
(def screen (Screen make 20 100))
(spec-draw! st screen)
(spec-keys! st (list (m 'press 'left 2 2)))
(def a (Vector ref 29 st))
(spec-draw! st screen)
(spec-keys! st (list (m 'wheel 'down 10 10)))
(def b (Vector ref 29 st))
(spec-keys! st (list (m 'press 'left 10 10)))
(def c (list (Vector ref 29 st) (Vector ref 17 st)))
(spec-draw! st screen)
(spec-keys! st (list ":song" 'enter))
(spec-draw! st screen)
(spec-keys! st (list (m 'press 'left 4 3)))
(write (list a b c (song-name (edit-song st)) (Vector ref 21 st)))
```
---
    ((0 . 0) (0 . 3) (() #f) "b" ())

### a click on F5 picks the channel, M mutes it

```tracker
(def m (fn (_ a b r c) (list 'mouse a b r c ())))
(def pl (player-open (spec-front) ()))
(def st (edit-make (file-parse "(song \"t\" (bpm 240) (rows 4)\n  (instrument lead (wave sine))\n  (instrument bass (wave sine))\n  (pattern p (lead \"C4 . E4 . G4 . . .\") (bass \"C2 . . . - . . .\"))\n  (order p))") () pl))
(spec-keys! st (list 'f5))
(spec-play! 30000)
(edit-tick! st)
(def screen (Screen make 20 100))
(spec-draw! st screen)
(spec-keys! st (list (m 'press 'left 6 10) "m"))
(player-stop! pl)
(write (list (Vector ref 6 st) (player-muted? pl 'channel 1)))
```
---
    (1 #t)
