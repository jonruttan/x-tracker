# The help
@weight 2

tracker/help: one source for ? and :help in the editor and the command
line's help word, and a check that it leaves nothing out.

## what it covers

### the topics

```tracker
(write (help-topics))
```
---
    ("keys" "commands" "cells" "effects" "song" "instruments" "waves" "order" "settings" "cli")

### every command the help names is one the editor knows

```tracker
(def unknown
  (List filter
    (fn (_ c)
      (def st (edit-make (file-parse "(song \"t\" (instrument a (wave sine)) (pattern p (a \"C4\")) (order p))") () ()))
      (spec-keys! st (list (Str8 append ":" c) 'enter))
      (Str8 starts? "No command" (edit-message st)))
    (help-commands)))
(write unknown)
```
---
    ()

### every command the editor dispatches has an entry

```tracker
(def text (File read-all (Str8 append %lang-root "/tracker/edit.x")))
(def from (Str8 index-of "(def %command!" text))
(def after (Str8 sub (+ from 1) (- (Str8 length text) (+ from 1)) text))
(def body (Str8 sub 0 (Str8 index-of "\n(def " after) after))
(def strings (fn (_ s) ((fn (_ ps) (List map (fn (_ i) (List ref i ps)) (List filter (fn (_ i) (Num odd? i)) (List range 0 (List length ps)))))
                         (Str8 split "\"" s))))
(def words
  (List filter (fn (_ w) (if (< 0 (Str8 length w)) (null? (Str8 index-of " " w)) #f))
    (List flat-map (fn (_ seg) (if (if (Str8 starts? "\"" seg) #t (Str8 starts? "(list " seg)) (strings (Str8 sub 0 (Str8 index-of ")" seg) seg)) ()))
      (rest (Str8 split "cmd " body)))))
(write (list (< 40 (List length words)) (List filter (fn (_ w) (null? (help-on w))) words)))
```
---
    (#t ())

### every action a key can be bound to, and every setting, has an entry

```tracker
(def lines (config-lines (config-default)))
(def actions (List map (fn (_ l) (List ref 3 (Str8 split " " l))) (List filter (fn (_ l) (Str8 starts? "  key " l)) lines)))
(def settings (List map (fn (_ l) (List ref 2 (Str8 split " " l)))
                (List filter (fn (_ l) (not (if (Str8 starts? "  key " l) #t (Str8 starts? "  colour " l)))) (rest lines))))
(def bound (List map symbol->str (help-key-actions)))
(write (list (List filter (fn (_ a) (not (List includes? a bound))) actions)
             (List filter (fn (_ s) (null? (help-on s))) settings)))
```
---
    (() ())

## looking up

### a word is every entry named it: a command with or without its colon, an effect with or without its slash

```tracker
(spec-lines (Str8 join "\n" (help-on ":loop")))
(spec-lines (Str8 join "\n" (help-on "/v")))
(spec-lines (Str8 join "\n" (help-on "gain")))
(write (help-on "nothing"))
```
---
```output
command  :loop [FROM TO]
  loop rows FROM to TO of the pattern; alone, the whole pattern
cell effect  /vD,P
  vibrato: D cents either way, a cycle every P ticks
command  :gain PCT
  the block marked, or the cell, at PCT percent, 0-400
instrument prop  (gain PCT)
  the voice's level
()
```

### a topic's lines start with what it is

```tracker
(spec-lines (Str8 join "\n" (List take 4 (help-topic "effects"))))
```
---
```output
effects: a cell's effects, after /
  /aX,Y,...     arpeggio: the note, then X, then Y ... semitones up, a tick each
  /vD,P         vibrato: D cents either way, a cycle every P ticks
  /sC           slide: C cents (below 0 down) by the next slide or the note's end, then held
```

## in the editor

### ? shows the index; n turns the page, the arrows scroll, another key closes it

```tracker
(def st (edit-make (file-parse "(song \"t\" (instrument a (wave sine)) (pattern p (a \"C4\")) (order p))") () ()))
(def screen (Screen make 10 100))
(spec-keys! st (list "?"))
(spec-draw! st screen)
(def index (Str8 trim-right (Screen row-text screen 2)))
(spec-keys! st (list "n" 'down 'down))
(spec-draw! st screen)
(spec-lines (spec-rows screen (List range 2 6)))
(spec-keys! st (list 'escape))
(spec-draw! st screen)
(write (list index (Str8 trim-right (Screen row-text screen 9))))
```
---
```output
keys: every key, and the action :set key binds it by   (2 above)   (32 below)
  q 2 w 3 e r 5 t 6 y 7 u i   a note, the octave above
  . or Delete                 hold: what sounds carries on
  -                           let go: what sounds fades over its release
("Help: :help TOPIC, or :help WORD for every command, effect, prop or setting named WORD   (4 below)" " ? help   Space play   p pattern   : command")
```

### :help TOPIC opens its page, :help WORD its entries, and a word with none is said

```tracker
(def st (edit-make (file-parse "(song \"t\" (instrument a (wave sine)) (pattern p (a \"C4\")) (order p))") () ()))
(def screen (Screen make 10 100))
(spec-keys! st (list ":help settings" 'enter))
(spec-draw! st screen)
(def topic (Str8 trim-right (Screen row-text screen 2)))
(spec-keys! st (list 'escape ":help mute" 'enter))
(spec-draw! st screen)
(def word (spec-rows screen (List range 2 4)))
(spec-keys! st (list 'escape ":help nothing" 'enter))
(spec-lines word)
(write (list topic (edit-message st)))
```
---
```output
command  :mute [INSTRUMENT]
  mute an instrument; alone, say what is muted and soloed
("settings: the settings file and :set   (8 below)" "No help on nothing; :help lists the topics.")
```

## on the command line

### help lists the topics, help WORD the entries, WORD -h the word's own

```tracker
(write (list (tracker-main (list "help" "cli")) (tracker-main (list "render" "-h")) (tracker-main (list "help" "nothing"))))
```
---
```output
cli: the command line's words and options
  x -l tracker -- [OPTIONS] [edit] [FILE]   the editor; with no FILE, a new song to write with :w FILE
                                            -s NAME the song to edit, -w FILE waves to read, -n no sound
  x -l tracker -- [OPTIONS] play FILE       play a song, the pattern heard written to standard error; q stops
                                            -s NAME the song (the file's first), -l loop it, -w FILE waves to read
  x -l tracker -- list FILE                 each song of FILE: how long it lasts, its patterns and its order
  x -l tracker -- render FILE -o OUT.wav    a song played once, to a WAV file
                                            -s NAME the song (the file's first), -w FILE waves to read
  x -l tracker -- help [WORD]               this help: the topics, a topic, or every entry named WORD
word  x -l tracker -- render FILE -o OUT.wav
  a song played once, to a WAV file
  -s NAME the song (the file's first), -w FILE waves to read
(0 0 1)
```
