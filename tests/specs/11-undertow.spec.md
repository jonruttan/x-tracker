# Undertow
@weight 2
# @timeout-scale 3

data/undertow.xon: its one song read by tracker/file, played once
through the tracker into the stand-in for SDL's audio at a tension of
50, so both layers sound, and rung out; then rendered to a WAV file.
Its forms are checked to be ones the tracker knows, so a misspelt
effect is caught here, and it plays on the file's waves and the
mixer's shaped ones.

The player is over only while the tracker renders the last row of the
ring-out, so the stand-in plays one block of 1024 frames a pump, less
than a row.

## the song

### the song plays through to its end on the file's waves and the mixer's

```tracker
(def udoc (file-read (Str8 append %lang-root "/data/undertow.xon")))
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
(write (List map (fn (_ s) (list (song-name s) (play-out (file-waves udoc) s))) (file-songs udoc)))
```
---
    (("undertow" #t))

### the song rendered at a tension of 50 is a WAV file of 48 to 60 seconds

```tracker
(import x/core/doors str-make str-byte-sub)
(def udoc (file-read (Str8 append %lang-root "/data/undertow.xon")))
(def path (rest (File temp "/tmp/x-tracker-spec-")))
(def pl (player-open () (file-waves udoc)))
(player-tension! pl 50)
(def frames (player-render! pl (first (file-songs udoc)) path))
(def fd (File open path 'rdonly))
(def size (File seek fd 0 'end))
(File seek fd 0)
(def head (str-make 44))
(File read fd head 44)
(File close fd)
(File unlink path)
(write (list (= size (+ 44 (* 4 frames))) (str-byte-sub head 0 4) (str-byte-sub head 8 8) (< (* 48 44100) frames) (< frames (* 60 44100))))
```
---
    (#t "RIFF" "WAVEfmt " #t #t)
