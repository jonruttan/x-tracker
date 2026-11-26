# The sample editor
@weight 2

tracker/sample's edits of a sound, and F3 as Schism Tracker's sample
list has it: a sample's settings, its sound edited on the Alt keys and
written back to its WAV file.

## the sound

### each edit answers the frames it should

```tracker
(def pcm (first (Bytes of-hex "0010ff7f0080fe00")))
(def fr (fn (_ s n) (List map (fn (_ i) (sample-frame s i)) (List range 0 n))))
(write (list (fr pcm 4)
  (fr (sample-reverse pcm 4) 4)
  (fr (sample-invert pcm 4) 4)
  (fr (sample-amplify pcm 4 0 4 50) 4)
  (fr (sample-silence pcm 4 1 3) 4)
  (fr (sample-fade pcm 4 0 4 #t) 4)
  (sample-mean pcm 4) (sample-peak pcm 4)
  (fr (sample-normalise (first (Bytes of-hex "00100020")) 2) 2)
  ((fn (_ c) (list (fr (first c) 2) (List ref 1 c))) (sample-cut pcm 4 1 3))
  ((fn (_ c) (list (fr (first c) 8) (List ref 1 c))) (sample-resample pcm 4 8 #t))
  ((fn (_ c) (fr (first c) 8)) (sample-resample pcm 4 8 #f))
  (sample-peaks pcm 4 2)
  (fr pcm 4)))
```
---
    ((4096 32767 -32768 254) (254 -32768 32767 4096) (-4096 -32767 32767 -254) (2048 16383 -16384 127) (4096 0 0 254) (0 8191 -16384 190) 1087 32768 (16383 32767) ((4096 254) 2) ((4096 18431 32767 -1 -32768 -16257 254 254) 8) (4096 4096 32767 32767 -32768 -32768 254 254) ((4096 . 32767) (-32768 . 254)) (4096 32767 -32768 254))

### a long sound's edits compiled write what pure x writes

```tracker
(def big (first (sample-resample (first (Bytes of-hex "00000040ff7f0040000000c00180ffbf")) 8 44100 #t)))
(def edits (fn (_) (list (sample-reverse big 44100) (sample-fade big 44100 0 44100 #f) (sample-centre big 44100)
                         (sample-normalise big 44100) (first (sample-resample big 44100 30000 #t)) (first (sample-resample big 44100 30000 #f)))))
(def e (Compiled named 'tracker-sample))
(def compiled (e state))
(def c (edits))
(e interpret!)
(def p (edits))
(e compile!)
(write (list compiled (List all? (fn (_ i) (equal? (List ref i c) (List ref i p))) (List range 0 6))))
```
---
    ('compiled #t)

## settings

### a sample's volume, global volume and pan are its instruments' gain and pan

```tracker
(def waves (list (lit (wave kick (sample "k.wav" (volume 32) (global 48) (pan 0)))) (lit (wave hat (sample "h.wav")))))
(def f (lit (song "t" (instrument a (wave kick) (gain 80) (pan 50)) (instrument b (wave hat)) (instrument c (wave sine)) (order p))))
(write (player-sampled f waves))
```
---
    ('song "t" ('instrument 'a ('wave 'kick) ('gain 30) ('pan -100)) ('instrument 'b ('wave 'hat)) ('instrument 'c ('wave 'sine)) ('order 'p))

## the page

### Tab walks the settings; left and right change one, Space turns a loop on and off

```tracker
(def dir (Str8 append ((fn (_ d) (if (null? d) "/tmp" d)) (Sys getenv "TMPDIR")) "/x-tracker-spec-samples"))
(unless (File exists? dir) (File mkdir dir))
(sample-write! (first (sample-resample (first (Bytes of-hex "00000040ff7f0040000000c00180ffbf")) 8 2000 #t)) 2000 8000 (Str8 append dir "/s.wav"))
(def st (edit-make (file-parse "(wave kick (sample \"s.wav\"))\n(song \"t\" (instrument a (wave kick)) (pattern p (a \"C4\")) (order p))") (Str8 append dir "/t.xon") ()))
(def form (fn (_) (List ref 2 (first (file-waves (edit-doc st))))))
(spec-keys! st (list 'f3 'complete 'left 'alt-left))
(def a (form))
(spec-keys! st (list 'complete 'complete " " 'right 'complete 'complete " " 'alt-right))
(def b (form))
(spec-keys! st (list 'complete 'complete 'complete 'complete 'complete 'complete 'complete 'right 'enter))
(write (list a b (form) (rest (Vector ref 12 st))))
```
---
    (('sample "s.wav" ('volume 55)) ('sample "s.wav" 31 2000 ('volume 55) ('pan 33)) ('sample "s.wav" 31 2000 ('volume 55) ('pan 33) ('vibrato 0 0 0 'ramp)) "sound set vib-wave ramp")

### the Alt keys edit the sound, ctrl-z undoes, Alt-O writes it, :q warns first

```tracker
(def dir (Str8 append ((fn (_ d) (if (null? d) "/tmp" d)) (Sys getenv "TMPDIR")) "/x-tracker-spec-samples"))
(unless (File exists? dir) (File mkdir dir))
(def path (Str8 append dir "/e.wav"))
(sample-write! (first (Bytes of-hex "0010ff7f0080fe00")) 4 8000 path)
(def st (edit-make (file-parse "(wave e (sample \"e.wav\" 1 3))\n(song \"t\" (instrument a (wave e)) (pattern p (a \"C4\")) (order p))") (Str8 append dir "/t.xon") ()))
(def heard (fn (_) (List map (fn (_ i) (sample-frame (List ref 2 (player-pcm 'e)) i)) (List range 0 (List ref 1 (player-pcm 'e))))))
(spec-keys! st (list 'f3 'alt-g))
(def a (heard))
(spec-keys! st (list 'alt-i 'ctrl-z))
(def b (heard))
(spec-keys! st (list 'alt-b))
(def c (list (heard) (List ref 2 (first (file-waves (edit-doc st))))))
(spec-keys! st (list ":q" 'enter))
(def warned (edit-message st))
(spec-keys! st (list 'alt-o))
(def d (Wav decode (File read-all path) 0 (Assoc get (lit size) (File stat path))))
(write (list a b c warned (Str8 starts? "Written: " (edit-message st)) (player-edited) (List ref 1 d)))
```
---
    ((254 -32768 32767 4096) (254 -32768 32767 4096) ((-32768 32767 4096) ('sample "e.wav" 0 2)) "The song has changed: :w writes it, :q! leaves without." #t () 3)

### a sound's edits and the song's are one history: ctrl-z and U undo either, ctrl-y and R redo

```tracker
(def dir (Str8 append ((fn (_ d) (if (null? d) "/tmp" d)) (Sys getenv "TMPDIR")) "/x-tracker-spec-samples"))
(unless (File exists? dir) (File mkdir dir))
(def path (Str8 append dir "/u.wav"))
(sample-write! (first (Bytes of-hex "0010ff7f0080fe00")) 4 8000 path)
(def st (edit-make (file-parse "(wave u (sample \"u.wav\"))\n(song \"t\" (instrument a (wave u)) (pattern p (a \". .\")) (order p))") (Str8 append dir "/t.xon") ()))
(def heard (fn (_) (List map (fn (_ i) (sample-frame (List ref 2 (player-pcm 'u)) i)) (List range 0 (List ref 1 (player-pcm 'u))))))
(def cells (fn (_) (rest (first (song-pattern (edit-song st) "p")))))
(spec-keys! st (list 'f3 'alt-g 'f2 "z"))
(def edited (list (heard) (cells)))
(spec-keys! st (list 'ctrl-z))
(def one (list (heard) (cells)))
(spec-keys! st (list 'f3 'ctrl-z))
(def two (list (heard) (edit-message st)))
(spec-keys! st (list 'ctrl-y))
(def redone (list (heard) (edit-message st)))
(spec-keys! st (list 'f2 "R"))
(def both (list (heard) (cells)))
(spec-keys! st (list "U" "U" "U"))
(write (list edited one two redone both (cells) (edit-message st)))
```
---
    (((254 -32768 32767 4096) ("C4" ".")) ((254 -32768 32767 4096) ("." ".")) ((4096 32767 -32768 254) "Undone: the sound of u.") ((254 -32768 32767 4096) "Redone: the sound of u.") ((254 -32768 32767 4096) ("C4" ".")) ("." ".") "Nothing to undo.")

### :sound edits over frames, refuses what it cannot do

```tracker
(def dir (Str8 append ((fn (_ d) (if (null? d) "/tmp" d)) (Sys getenv "TMPDIR")) "/x-tracker-spec-samples"))
(unless (File exists? dir) (File mkdir dir))
(sample-write! (first (Bytes of-hex "0010ff7f0080fe00")) 4 8000 (Str8 append dir "/f.wav"))
(def st (edit-make (file-parse "(wave f (sample \"f.wav\"))\n(song \"t\" (instrument a (wave f)) (pattern p (a \"C4\")) (order p))") (Str8 append dir "/t.xon") ()))
(def say (fn (_ line) (spec-keys! st (list 'f3 line 'enter)) (edit-message st)))
(write (list (say ":sound silence 1 3") (List map (fn (_ i) (sample-frame (List ref 2 (player-pcm 'f)) i)) (List range 0 4)) (say ":q")
             (say ":sound cut-before") (say ":sound amplify 5000") (say ":sound bogus") (say ":sound mono")
             (say ":sound resample 8") (List ref 2 (first (file-waves (edit-doc st))))))
```
---
    ("Sound of f: silence, 4 frames. Alt-O writes it." (4096 0 0 254) "The sound of f is edited: Alt-O on F3 writes it, :q! leaves without." "The sample has no loop: Tab to Loop start, then Space." ":sound amplify N, N from 0 to 1000." "No edit bogus: :sound alone lists them." "A sample is one channel already: the WAV reader takes the mean of a file's channels." "Sound of f: resample, 8 frames. Alt-O writes it." ('sample "f.wav" ('speed 16000)))

### F3 draws the settings beside the list and the sound beneath

```tracker
(def dir (Str8 append ((fn (_ d) (if (null? d) "/tmp" d)) (Sys getenv "TMPDIR")) "/x-tracker-spec-samples"))
(unless (File exists? dir) (File mkdir dir))
(sample-write! (first (sample-resample (first (Bytes of-hex "00000040ff7f0040000000c00180ffbf")) 8 2000 #t)) 2000 8000 (Str8 append dir "/d.wav"))
(def st (edit-make (file-parse "(wave kick (sample \"d.wav\" 100 1900 (sustain 10 20)))\n(song \"t\" (instrument a (wave kick)) (pattern p (a \"C4\")) (order p))") (Str8 append dir "/t.xon") ()))
(def screen (Screen make 30 80))
(spec-keys! st (list 'f3 'complete))
(spec-draw! st screen)
(write (List map (fn (_ i) (Str8 trim-right (Screen row-text screen i))) (List range 3 29)))
```
---
    (" Sample list                                Settings of kick" "" "  kick           d.wav                      Default volume  64" "                                            Global volume   64" "                                            Default pan     off" "                                            C-5 speed       8000 Hz" "                                            Loop start      100" "                                            Loop end        1900" "                                            Sustain start   10" "                                            Sustain end     20" "                                            Vibrato speed   0" "                                            Vibrato depth   0" "                                            Vibrato rate    0" "                                            Vibrato wave    sine" "" " Sound   2000 frames, 0.25 s at C-5   Alt-O writes it to d.wav" "              ||||||||||||||" "       ||||||||            |||||||" " |||||||                         ||||||||" "                                        |||||||" "                                              ||||||||            |||||||||||||" "                                                     ||||||||||||||" "" " }  [                                                                      ]" " Sustain loops and vibrato are kept, and not heard: the mixer has neither." "")
