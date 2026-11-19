# The player
@weight 2

tracker/player through a stand-in for SDL's audio: a front that counts
what is put on a stream and plays it only as the spec says, with
spec-play!.  Nothing here opens an audio device.

## playing

### a song played once rings out and is over; its place moves through the order

```tracker
(def pl (player-open (spec-front) ()))
(player-start! pl spec-tune 'once 0 ())
(def places ())
(def spin (fn (self n) (if (if (< 0 n) (not (player-over? pl)) #f)
                         (do (spec-play! 4096) (player-pump! pl) (set! places (pair (first (player-place pl)) places)) (self (- n 1))) n)))
(def left (spin 400))
(write (list (player-playing? pl) (player-over? pl) (< 0 left) (List includes? 0 places) (List includes? 1 places)))
```
---
    (#t #t #t #t #t)

### a song played from a place starts there; stopping it clears its stream

```tracker
(def pl (player-open (spec-front) ()))
(player-start! pl spec-tune 'song 1 ())
(player-pump! pl)
(def at (first (player-place pl)))
(player-stop! pl)
(write (list at (player-playing? pl) (player-queued pl)))
```
---
    (1 #f 0)

### at a pattern's end its last row is heard, not the next pattern's first

```tracker
(def pl (player-open (spec-front) ()))
(player-start! pl spec-tune 'song 0 ())
(player-pump! pl)
(spec-play! 38000)
(def ending (player-place pl))
(spec-play! 8000)
(def begun (player-place pl))
(player-start! pl spec-tune 'pattern 0 "q")
(player-pump! pl)
(spec-play! 38000)
(write (list ending begun (player-place pl)))
```
---
    ((0 . 3) (1 . 0) (0 . 3))

### a pattern played alone keeps to it, and a song the tracker cannot read is refused

```tracker
(def pl (player-open (spec-front) ()))
(player-start! pl spec-tune 'pattern 0 "q")
(def spin (fn (self n) (when (< 0 n) (do (player-pump! pl) (self (- n 1))))))
(spin 40)
(def at (first (player-place pl)))
(write (list at (guard (e (e msg)) (player-start! pl (song-set-order spec-tune (list "nope")) 'song 0 ()))))
```
---
    (0 "Tracker: no pattern named nope")

### a change while a song plays is taken from the next pattern; a note typed is heard

```tracker
(def pl (player-open (spec-front) ()))
(player-start! pl spec-tune 'song 0 ())
(player-pump! pl)
(player-update! pl (song-set-order spec-tune (list "q" "p" "q")) ())
(player-preview! pl spec-tune "a" "A4")
(spec-play! 4096)
(write (list (< 0 (player-pump! pl)) (player-playing? pl)))
```
---
    (#t #t)

### a song naming a wave the mixer lacks is refused before it plays, and a waves file mends it

```tracker
(def s (song-parse "(song \"s\" (bpm 240) (rows 4)\n  (instrument a (wave spec-reedy))\n  (pattern p (a \"C4 . E4 .\"))\n  (order p))"))
(def pl (player-open (spec-front) ()))
(def refused (guard (e (e msg)) (player-start! pl s 'song 0 ())))
(def heard (guard (e (e msg)) (player-preview! pl s "a" "C4")))
(def pl2 (player-open (spec-front) (list '(wave spec-reedy 6 0 3))))
(player-start! pl2 s 'song 0 ())
(player-pump! pl2)
(write (list refused (str=? refused heard) (player-playing? pl2)))
```
---
    ("x-tracker: no wave named spec-reedy: read the file its (wave ...) form is in with -w FILE" #t #t)

### a wave of points is drawn by its points, and one of harmonics by its harmonics

```tracker
(import x/core/doors ptr-ref-word int->ptr)
(def pl (player-open (spec-front) (list '(wave spec-stair (0 100) (1 100) (1 -100) (2 -100)) '(wave spec-pair 1 1))))
(def at (fn (_ name i) (ptr-ref-word (int->ptr (List ref 1 (Mixer wave name))) (* i %word-size))))
(def s (song-parse "(song \"s\" (bpm 240) (rows 2)\n  (instrument a (wave spec-stair))\n  (pattern p (a \"C4 .\"))\n  (order p))"))
(player-start! pl s 'song 0 ())
(player-pump! pl)
(write (list (at 'spec-stair 0) (at 'spec-stair 1023) (at 'spec-stair 1024) (< (at 'spec-pair 300) 32768) (player-playing? pl)))
```
---
    (32767 32767 -32767 #t #t)

## the editor playing

### a borrowed wave is kept in the file, and a wave made is heard; undo puts the mixer back

```tracker
(def wdoc (file-parse "(wave spec-own 3 1)\n\n(song \"s\" (bpm 240) (rows 4)\n  (instrument a (wave spec-lent))\n  (instrument b (wave spec-own))\n  (instrument c (wave sine))\n  (pattern p (a \"C4\") (b \"C4\") (c \"C4\"))\n  (order p))\n"))
(def pl (player-open (spec-front) (List append (file-waves wdoc) (list '(wave spec-lent 5 0 1) '(wave spec-spare 1 1)))))
(def st (edit-make wdoc () pl))
(def screen (Screen make 8 100))
(def lent (fn (_) (List find (fn (_ w) (eq? (List ref 1 w) 'spec-lent)) (player-waves pl))))
(spec-keys! st (list ":waves" 'enter))
(spec-draw! st screen)
(spec-lines (spec-rows screen (List range 2 6)))
(spec-keys! st (list 'escape ":waves keep" 'enter))
(def kept (list (edit-message st) (file-wave (edit-doc st) "spec-lent") (file-changed? (edit-doc st))))
(spec-keys! st (list ":wave spec-lent 1 0 0 1" 'enter))
(def made (list (edit-message st) (file-wave (edit-doc st) "spec-lent") (lent)))
(spec-keys! st (list "U" "U"))
(def undone (list (file-wave (edit-doc st) "spec-lent") (lent)))
(spec-keys! st (list ":wave sine 1" 'enter))
(def own (edit-message st))
(spec-keys! st (list ":wave square 1" 'enter))
(def own2 (edit-message st))
(spec-keys! st (list ":wave spec-x 0 0" 'enter))
(write (list kept made undone own own2 (edit-message st)))
```
---
```output
Waves   :wave NAME AMP ... makes or changes one   :waves keep copies the borrowed ones in
  spec-lent   borrowed (-w)    5 0 1
  spec-own    in the file      3 1
  sine        the mixer's own
(("Kept in the file: spec-lent." ('wave 'spec-lent 5 0 1) #t) ("Wave spec-lent: 1 0 0 1." ('wave 'spec-lent 1 0 0 1) ('wave 'spec-lent 1 0 0 1)) (() ('wave 'spec-lent 5 0 1)) "sine is the mixer's own." "square is the mixer's own." "A wave's harmonics are whole numbers from 0, not all 0: (wave hollow 6 0 2 0 1).")
```

### the editor follows the pattern and row heard, until F stops it

```tracker
(def parsed (file-parse (song-text spec-tune)))
(def st (edit-make parsed () (player-open (spec-front) ())))
(spec-keys! st (list " "))
(def spin (fn (self n seen) (if (< 0 n) (do (spec-play! 4096) (edit-tick! st) (self (- n 1) (if (List includes? (first (edit-place st)) seen) seen (pair (first (edit-place st)) seen)))) seen)))
(def seen (spin 60 ()))
(spec-keys! st (list "F"))
(def at (edit-place st))
(spin 30 ())
(write (list (List includes? "p" seen) (List includes? "q" seen) (edit-message st) (equal? at (edit-place st))))
```
---
    (#t #t "Not following the playing." #t)

### a note typed is made from its own instrument alone, and cuts off the one before

```tracker
(def s (song-parse "(song \"s\" (bpm 240) (rows 4)\n  (instrument a (wave sine))\n  (instrument b (wave spec-missing))\n  (pattern p (a \"C4 . E4 .\") (b \"C3\"))\n  (order p))"))
(def pl (player-open (spec-front) ()))
(player-preview! pl s "a" "C4")
(player-pump! pl)
(def first-queued (< 0 (Vector ref 1 spec-streams)))
(player-preview! pl s "a" "E4")
(def cleared (Vector ref 1 spec-streams))
(write (list first-queued cleared (guard (e (e msg)) (player-preview! pl s "b" "C3") "played")))
```
---
    (#t 0 "x-tracker: no wave named spec-missing: read the file its (wave ...) form is in with -w FILE")

### a song loaded starts afresh: the playing stopped, and an undo goes back to its own song

```tracker
(def two (file-parse (Str8 append (song-text spec-tune) "\n(song \"t\" (instrument a (wave sine)) (pattern r (a \"C4\")) (order r))\n")))
(def st (edit-make two () (player-open (spec-front) ())))
(spec-keys! st (list "x" " "))
(spec-play! 8000)
(edit-tick! st)
(def playing (player-playing? (edit-player st)))
(spec-keys! st (list ":song t" 'enter))
(def after (list (song-name (edit-song st)) (player-playing? (edit-player st)) (edit-place st)))
(spec-keys! st (list "U"))
(def p-first (fn (_) (pattern-cell (song-pattern (edit-song st) "p") 0 0)))
(write (list playing after (song-name (edit-song st)) (first (edit-place st)) (p-first)))
```
---
    (#t ("t" #f ("r" 0 0)) "s" "p" "C4")
