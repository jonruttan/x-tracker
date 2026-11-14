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
(spec-keys! st (list ":wave spec-x 0 0" 'enter))
(write (list kept made undone own (edit-message st)))
```
---
```output
Waves   :wave NAME AMP ... makes or changes one   :waves keep copies the borrowed ones in
  spec-lent   borrowed (-w)    5 0 1
  spec-own    in the file      3 1
  sine        the mixer's own
(("Kept in the file: spec-lent." ('wave 'spec-lent 5 0 1) #t) ("Wave spec-lent: 1 0 0 1." ('wave 'spec-lent 1 0 0 1) ('wave 'spec-lent 1 0 0 1)) (() ('wave 'spec-lent 5 0 1)) "sine is the mixer's own." "A wave's harmonics are whole numbers from 0, not all 0: (wave hollow 6 0 2 0 1).")
```

### the editor follows the pattern and row heard, until F stops it

```tracker
(def doc (file-parse (song-text spec-tune)))
(def st (edit-make doc () (player-open (spec-front) ())))
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
