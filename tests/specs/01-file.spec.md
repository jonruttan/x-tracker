# Files and songs
@weight 1

tracker/node, tracker/file and tracker/song: a .xon file read into a
document and written back, and the songs in it.

## reading and writing

### a file is written back byte for byte when nothing changed

```tracker
(def text "; songs\n(wave hollow 6 0 2)\n\n(song \"hum\" (bpm 60) (rows 2)\n  ; the voice\n  (instrument a (wave sine) (env (0 0) (5 80)))\n  (pattern p (a \"C3 . E3 .\"))\n  (order p))  ; end\n")
(def doc (file-parse text))
(write (list (str=? (file-text doc) text) (List map first doc) (file-changed? doc)))
```
---
    (#t ('gap 'form 'gap 'song 'gap) #f)

### the waves of a file are its wave forms

```tracker
(write (file-waves (file-parse "(wave hollow 6 0 2)\n(song \"s\" (pattern p (a \"C3\")) (order p))\n(wave thin 2 0 3)")))
```
---
    (('wave 'hollow 6 0 2) ('wave 'thin 2 0 3))

### a wave set in a file takes its form's place, or a line after the last wave, or before the first song

```tracker
(def two "; w\n(wave hollow 6 0 2)\n\n(song \"s\" (instrument a (wave hollow)) (instrument b (wave thin)) (pattern p (a \"C3\")) (order p))\n")
(def changed (file-set-wave (file-parse two) "hollow" (list 4 0 1)))
(def added (file-set-wave (file-parse two) "thin" (list 2 0 3)))
(def first-one (file-set-wave (file-parse "(song \"s\" (pattern p (a \"C3\")) (order p))\n") "reed" (list 6 4)))
(write (list (file-text changed) (file-text added) (file-text first-one)
             (file-changed? added) (file-changed? (file-written added)) (file-wave added "thin")
             (song-waves (first (file-songs added)))))
```
---
    ("; w\n(wave hollow 4 0 1)\n\n(song \"s\" (instrument a (wave hollow)) (instrument b (wave thin)) (pattern p (a \"C3\")) (order p))\n" "; w\n(wave hollow 6 0 2)\n(wave thin 2 0 3)\n\n(song \"s\" (instrument a (wave hollow)) (instrument b (wave thin)) (pattern p (a \"C3\")) (order p))\n" "(wave reed 6 4)\n\n(song \"s\" (pattern p (a \"C3\")) (order p))\n" #t #f ('wave 'thin 2 0 3) ("hollow" "thin"))

### a song is read into its name, its props, its patterns and its order

```tracker
(def s (song-parse "(song \"hum\" (bpm 72) (rows 2)\n  (instrument a (wave sine))\n  (instrument b (wave noise))\n  (pattern p (a \"C3 . E3 .\") (b \". C4\"))\n  (pattern q (a \"G3\"))\n  (order p q p))"))
(write (list (song-name s) (song-prop s "bpm" 90) (song-prop s "ticks" 6) (song-instruments s)
             (song-patterns s) (song-order s)))
```
---
    ("hum" 72 6 ("a" "b") (("p" ("a" "C3" "." "E3" ".") ("b" "." "C4")) ("q" ("a" "G3"))) ("p" "q" "p"))

### a song unchanged in a file stays as written, a changed one is written from the song

```tracker
(def text "(song \"hum\" (bpm 60)\n  ; kept until the song changes\n  (instrument a (wave sine))\n  (pattern p (a \"C3 . E3 .\"))\n  (order p))\n")
(def doc (file-parse text))
(def s (first (file-songs doc)))
(def chs (song-pattern s "p"))
(def doc2 (file-song! doc 0 (song-set-pattern s "p" (pattern-set-cell chs 0 1 "D#3/v20,4"))))
(spec-lines (file-text doc2))
(write (list (file-changed? doc2) (file-changed? (file-written doc2))))
```
---
```output
(song "hum" (bpm 60)
  (instrument a (wave sine))
  (pattern p
    (a "C3 D#3/v20,4 E3 ."))
  (order p))

(#t #f)
```

### the text a song is written as reads back as the same song

```tracker
(def s (song-parse "(song \"hum\" (bpm 60) (rows 4)\n  (instrument lead (wave sine) (env (0 0) (5 80) (300 0)))\n  (instrument bass (wave hollow))\n  (pattern p (lead \"C4 . E4:50 . G4/v30,4 .\") (bass \"C2 . . . - .\"))\n  (order p p))"))
(def again (song-parse (song-text s)))
(write (equal? again s))
(display "\n")
(spec-lines (song-text s))
```
---
```output
#t
(song "hum" (bpm 60) (rows 4)
  (instrument lead (wave sine) (env (0 0) (5 80) (300 0)))
  (instrument bass (wave hollow))
  (pattern p
    (lead "C4    .     E4:50 .     G4/v30,4 .")
    (bass "C2    .     .     .     -     ."))
  (order p p))
```

### a file whose parentheses do not pair is refused

```tracker
(write (list (guard (e (e msg)) (file-parse "(song \"a\" (bpm 60)"))
             (guard (e (e msg)) (file-parse "(a))"))
             (guard (e (e msg)) (file-parse "(a \"open)"))))
```
---
    ("x-tracker: a ( is never closed" "x-tracker: a ) closes nothing" "x-tracker: a string is never closed")

## changing a song

### a prop is changed in its place, or put on the song's first line

```tracker
(def s (song-parse "(song \"hum\" (bpm 60)\n  (instrument a (wave sine))\n  (pattern p (a \"C3\"))\n  (order p))"))
(spec-lines (song-text (song-set-prop (song-set-prop s "bpm" 96) "ticks" 3)))
```
---
```output
(song "hum" (bpm 96) (ticks 3)
  (instrument a (wave sine))
  (pattern p
    (a "C3"))
  (order p))
```

### a new pattern goes after the others, and an instrument after the instruments

```tracker
(def s (song-parse "(song \"hum\"\n  (instrument a (wave sine))\n  (pattern p (a \"C3\"))\n  (order p))"))
(def s2 (song-set-instrument (song-set-pattern s "q" (list (list "a" "E3" "."))) "(instrument b (wave noise) (hz 1))"))
(spec-lines (song-text (song-set-order s2 (list "p" "q"))))
(write (guard (e (e msg)) (song-set-instrument s "(pattern x)")))
```
---
```output
(song "hum"
  (instrument a (wave sine))
  (instrument b (wave noise) (hz 1))
  (pattern p
    (a "C3"))
  (pattern q
    (a "E3 ."))
  (order p q))
"x-tracker: an instrument is (instrument NAME PROP ...)"
```

### rows are inserted and deleted in every channel, the pattern's length kept

```tracker
(def chs (list (list "a" "C3" "D3" "E3") (list "b" "." "G2")))
(write (list (pattern-insert-row chs 1) (pattern-delete-row chs 0) (pattern-resize chs 2) (pattern-rows (pattern-add-channel chs "c"))))
```
---
    ((("a" "C3" "." "D3") ("b" "." "." "G2")) (("a" "D3" "E3" ".") ("b" "G2" "." ".")) (("a" "C3" "D3") ("b" "." "G2")) 3)

### the form a song plays as is the tracker's, its order replaced when asked

```tracker
(def s (song-parse "(song \"hum\" (bpm 60)\n  (instrument a (wave sine))\n  (pattern p (a \"C3 . E3\"))\n  (order p p))"))
(write (list (song-form s ()) (List last (song-form s (list "p")))))
```
---
    (('song "hum" ('bpm 60) ('instrument 'a ('wave 'sine)) ('pattern 'p ('a "C3 . E3")) ('order 'p 'p)) ('order 'p))

### a cell is a note, a hold or a release, with effects

```tracker
(write (List map song-cell-problem (list "C4" "C#4:50/v20,4" "." "-/c2" "H4" "" "C4 D4")))
```
---
    (() () () () "no note H4" "an empty cell" "a cell has no spaces")
