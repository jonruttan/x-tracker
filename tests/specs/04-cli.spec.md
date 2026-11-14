# The command line
@weight 1

tracker/cli: what the words and options do, short of opening the
terminal or the audio.

## words

### list prints each song of a file: its length, patterns and order

```tracker
(write (tracker-main (list "list" (Str8 append %lang-root "/data/demo.xon"))))
```
---
```output
lantern  0:12  3 patterns  order intro tune turn tune turn
lighthouse  0:22  6 patterns  order intro verse turn verse fill bridge verse turn outro
0
```

### -V prints the version, and an unknown option or a missing file is refused

```tracker
(write (list (tracker-main (list "-V")) (tracker-main (list "--nope")) (tracker-main (list "play")) (tracker-main (list "a" "b"))))
```
---
    (0 2 2 2)

### a song the file does not have cannot be played

```tracker
(write (tracker-main (list "-s" "nope" "play" (Str8 append %lang-root "/data/demo.xon"))))
```
---
    1
