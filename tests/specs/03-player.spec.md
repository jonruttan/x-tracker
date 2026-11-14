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

## the editor playing

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
