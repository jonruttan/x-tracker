# The demo
@weight 2
# @timeout-scale 2

data/demo.xon: every song in it read by tracker/file, played once
through the tracker into the stand-in for SDL's audio at a tension of
50, so both layers sound, and rung out.  The tracker passes over a form
of a song it does not know, so each song's forms are checked to be ones
it does: a misspelt effect is caught here.

## the demo

### every song of data/demo.xon plays through to its end

```tracker
(def wdoc (file-read (Str8 append %lang-root "/data/demo.xon")))
(def play-out
  (fn (_ waves s)
    (guard (e (e msg))
      (def pl (player-open (spec-front) waves))
      (player-tension! pl 50)
      (player-start! pl s 'once 0 ())
      (def spin (fn (self n) (if (if (< 0 n) (not (player-over? pl)) #f) (do (spec-play! 1000000) (player-pump! pl) (Heap collect) (self (- n 1))) n)))
      (def unknown
        (List filter (fn (_ h) (not (List includes? h '(bpm rows ticks tension-bpm echo reverb phase chorus drive crush sweep limit instrument pattern order))))
          (List map first (List filter pair? (rest (rest (song-form s ())))))))
      (if (null? unknown) (< 0 (spin 600)) unknown))))
(write (List map (fn (_ s) (list (song-name s) (play-out (file-waves wdoc) s))) (file-songs wdoc)))
```
---
    (("lantern" #t) ("lighthouse" #t))

