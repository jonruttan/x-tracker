# Writing music
@weight 2

docs/writing.md and data/demo.xon: every song in them read by
tracker/file, played once through the tracker into the stand-in for
SDL's audio at a tension of 50, so both layers sound, and rung out.
Each `xon` block of the guide is a file of its own.  The tracker passes
over a form of a song it does not know, so each song's forms are
checked to be ones it does: a misspelt effect is caught here.

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

## the guide

### every xon block of docs/writing.md reads, and each of its songs plays through to its end

```tracker
(def text (File read-all (Str8 append %lang-root "/docs/writing.md")))
(def blocks
  (rest (List fold
          (fn (_ acc line)
            (match ((str=? line "```xon") (pair "" (rest acc)))
                   ((null? (first acc)) acc)
                   ((str=? line "```") (pair () (pair (first acc) (rest acc))))
                   (#t (pair (Str8 append (first acc) line "\n") (rest acc)))))
          (pair () ()) (Str8 split "\n" text))))
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
(def results
  (List flat-map
    (fn (_ b)
      (guard (e (list (list b (e msg))))
        (def bdoc (file-parse b))
        (List map (fn (_ s) (list (song-name s) (play-out (file-waves bdoc) s))) (file-songs bdoc))))
    blocks))
(write (list (< 10 (List length blocks)) (List filter (fn (_ r) (not (eq? (List ref 1 r) #t))) results)))
```
---
    (#t ())
