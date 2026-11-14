# The player
@weight 2

tracker/player through a stand-in for SDL's audio: a front that takes
what is put on a stream and plays 1024 bytes of it each time it is asked
how much is queued.  Nothing here opens an audio device.

## playing

### a song played once rings out and is over; its place moves through the order

```tracker
(def pl (player-open (spec-front) ()))
(player-start! pl spec-tune 'once 0 ())
(def places ())
(def spin (fn (self n) (if (if (< 0 n) (not (player-over? pl)) #f)
                         (do (player-pump! pl) (set! places (pair (first (player-place pl)) places)) (self (- n 1))) n)))
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
(write (list (< 0 (player-pump! pl)) (player-playing? pl)))
```
---
    (#t #t)
