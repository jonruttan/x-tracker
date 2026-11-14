# The Hungarian Dance
@weight 2
# @timeout-scale 6

data/hungarian-dance-5.xon: its one song read by tracker/file, played
once through the tracker into the stand-in for SDL's audio at a tension
of 50, so both layers sound, and rung out.  Its forms are checked to be
ones the tracker knows, so a misspelt effect is caught here, and it
plays on the file's waves and the mixer's shaped ones.

The player is over only while the tracker renders the last row of the
ring-out, so the stand-in plays one block of 1024 frames a pump, less
than a row: a pump of a second can step past that row, and the song
comes round to its start.

## the dance

### the song plays through to its end on the file's waves and the mixer's

```tracker
(def hdoc (file-read (Str8 append %lang-root "/data/hungarian-dance-5.xon")))
(def play-out
  (fn (_ waves s)
    (guard (e (e msg))
      (def pl (player-open (spec-front) waves))
      (player-tension! pl 50)
      (player-start! pl s 'once 0 ())
      (def spin (fn (self n) (if (if (< 0 n) (not (player-over? pl)) #f) (do (spec-play! 4096) (player-pump! pl) (when (= 0 (% n 64)) (Heap collect)) (self (- n 1))) n)))
      (def unknown
        (List filter (fn (_ h) (not (List includes? h '(bpm rows ticks tension-bpm echo reverb phase chorus drive crush sweep limit instrument pattern order))))
          (List map first (List filter pair? (rest (rest (song-form s ())))))))
      (if (null? unknown) (< 0 (spin 12000)) unknown))))
(write (List map (fn (_ s) (list (song-name s) (play-out (file-waves hdoc) s))) (file-songs hdoc)))
```
---
    (("hungarian-dance-5" #t))
