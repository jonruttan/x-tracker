# The settings
@weight 2

tracker/config: the user's file, read as data, and :set in the editor.

## the file

### the file is $X_TRACKER_CONFIG, else under $XDG_CONFIG_HOME, else ~/.config

```tracker
(def was (list (Sys getenv "X_TRACKER_CONFIG") (Sys getenv "XDG_CONFIG_HOME")))
(Sys setenv "X_TRACKER_CONFIG" "/a/t.xon")
(def named (config-file))
(Sys setenv "X_TRACKER_CONFIG" "")
(def none (config-file))
(Sys unsetenv "X_TRACKER_CONFIG")
(Sys setenv "XDG_CONFIG_HOME" "/c")
(def xdg (config-file))
(Sys unsetenv "XDG_CONFIG_HOME")
(def home (Str8 ends? "/.config/x/tracker.xon" (config-file)))
(unless (null? (first was)) (Sys setenv "X_TRACKER_CONFIG" (first was)))
(unless (null? (List ref 1 was)) (Sys setenv "XDG_CONFIG_HOME" (List ref 1 was)))
(write (list named none xdg home))
```
---
    ("/a/t.xon" () "/c/x/tracker.xon" #t)

### no file is the defaults

```tracker
(def cfg (config-read "/no/such/tracker.xon"))
(write (List map (fn (_ n) (config-get cfg n)) (list 'octave 'step 'follow 'backup 'undo 'sound 'waves)))
(write (config-problems cfg))
```
---
    (4 1 #t #t 200 #t ())()

### each form is a setting; one that is not is a problem, the rest still read

```tracker
(def dir ((fn (_ d) (if (null? d) "/tmp" d)) (Sys getenv "TMPDIR")))
(def path (Str8 append dir "/x-tracker-spec-config.xon"))
(File write-all path "; settings\n(octave 3) (step 2) (follow off) (backup no)\n(undo 5) (sound off) (waves \"sounds.xon\" \"/abs/w.xon\")\n(octave 12) (tempo 3)\n(colour beat (bold) red ())\n(key undo \"u\")\n")
(def cfg (config-read path))
(File unlink path)
(write (List map (fn (_ n) (config-get cfg n)) (list 'octave 'step 'follow 'backup 'undo 'sound)))
(write (list (str=? (first (config-get cfg 'waves)) (Str8 append dir "/sounds.xon"))))
(write (List ref 1 (config-get cfg 'waves)))
(spec-lines (Str8 join "\n" (List map (fn (_ p) (Str8 sub (Str8 length path) (- (Str8 length p) (Str8 length path)) p)) (config-problems cfg))))
(write (list (= (config-style cfg 'beat) (Style make '(bold) 1 ())) (config-key cfg "u") (config-key cfg "U") (config-key cfg "x")))
```
---
```output
(3 2 #f #f 5 #f)(#t)"/abs/w.xon": (octave 12): octave is a number from 0 to 8
: (tempo 3): no setting tempo
(#t "U" () "x")
```

### a file that does not read is one problem and the defaults

```tracker
(def path (Str8 append ((fn (_ d) (if (null? d) "/tmp" d)) (Sys getenv "TMPDIR")) "/x-tracker-spec-bad.xon"))
(File write-all path "(octave 3\n")
(def cfg (config-read path))
(File unlink path)
(write (list (config-get cfg 'octave) (List length (config-problems cfg)) (Str8 ends? "unreadable -- the defaults are used" (first (config-problems cfg)))))
```
---
    (4 1 #t)

### colours take numbers, names and bright names; a bad one is refused

```tracker
(def cfg (config-default))
(write (list (config-set! cfg '(colour off () bright-blue 0) #f) (= (config-style cfg 'off) (Style make () 12 0))
             (config-set! cfg '(colour off () 300) #f) (config-set! cfg '(colour off (blink)) #f)
             (config-set! cfg '(colour nope ()) #f)))
```
---
    (() #t "a colour is 0 to 255, a name (red, bright-blue ...), or ()" "the attributes are a list of bold dim italic underline reverse strike: (bold), ()" "colour NAME ATTRIBUTES FOREGROUND BACKGROUND, NAME one of title empty heading beat off effect cursor playing block")

## :set

### :set NAME VALUE changes a setting for the session; the octave and step at once

```tracker
(def st (edit-make (file-parse "(song \"t\" (instrument a (wave sine)) (pattern p (a \". . . .\")) (order p))") () ()))
(spec-keys! st (list ":set octave 2" 'enter ":set step 2" 'enter "z" ":set follow off" 'enter))
(def msg (edit-message st))
(spec-keys! st (list ":set octave 9" 'enter))
(def bad (edit-message st))
(spec-keys! st (list ":set sound off" 'enter))
(write (list (song-pattern (edit-song st) "p") msg bad (edit-message st)))
```
---
    ((("a" "C2" "." "." ".")) "Set: follow off" "octave is a number from 0 to 8" "sound is read as the editor starts: the config file or -n")

### a key bound to an action does it, and the action's own key no longer does

```tracker
(def st (edit-make (file-parse "(song \"t\" (instrument a (wave sine)) (pattern p (a \". . . .\")) (order p))") () ()))
(spec-keys! st (list ":set key octave-up \"o\"" 'enter "o" ">" "z"))
(def typed (song-pattern (edit-song st) "p"))
(spec-keys! st (list ":set key octave-up" 'enter ">" "z"))
(write (list typed (song-pattern (edit-song st) "p")))
```
---
    ((("a" "C5" "." "." ".")) (("a" "C5" "C6" "." ".")))

### :set alone lists the settings, the keys among them

```tracker
(def cfg (config-default))
(def st (edit-make (file-parse "(song \"t\" (instrument a (wave sine)) (pattern p (a \"C4\")) (order p))") () () cfg))
(def screen (Screen make 30 160))
(spec-keys! st (list ">" ":set" 'enter))
(spec-draw! st screen)
(spec-lines (spec-rows screen (List range 3 12)))
(write (List includes? "  key play Space" (config-lines cfg)))
```
---
```output
  octave 5                         key octave-up ">"                key play-here "G"
  step 1                           key step-down "{"                key loop "L"
  follow on                        key step-up "}"                  key mute-channel "M"
  backup on                        key up up                        key solo-channel "S"
  undo 200                         key down down                    key mute-instrument "H"
  sound on                         key left left                    key solo-instrument "A"
  waves                            key right right                  key tension-down ";"
  colour title (reverse) () ()     key page-up page-up              key tension-up "'"
  colour empty (dim) () ()         key page-down page-down          key pace-down "_"
#t
```

### the undo setting is how many changes are kept to undo

```tracker
(def st (edit-make (file-parse "(song \"t\" (instrument a (wave sine)) (pattern p (a \". . . .\")) (order p))") () ()))
(spec-keys! st (list ":set undo 2" 'enter "zxcv" "UUUU"))
(write (list (song-pattern (edit-song st) "p") (edit-message st)))
```
---
    ((("a" "C4" "D4" "." ".")) "Nothing to undo.")

### :w writes a backup of the file first, once a session, when backup is on

```tracker
(def path (Str8 append ((fn (_ d) (if (null? d) "/tmp" d)) (Sys getenv "TMPDIR")) "/x-tracker-spec-bak.xon"))
(File write-all path "(song \"a\" (instrument a (wave sine)) (pattern p (a \"C4\")) (order p))\n")
(def st (edit-make (file-read path) path ()))
(spec-keys! st (list "x" ":w" 'enter "c" ":w" 'enter))
(def bak (File read-all (Str8 append path ".bak")))
(File unlink (Str8 append path ".bak"))
(spec-keys! st (list ":set backup off" 'enter "v" ":w" 'enter))
(def none (File exists? (Str8 append path ".bak")))
(File unlink path)
(spec-lines bak)
(write none)
```
---
```output
(song "a" (instrument a (wave sine)) (pattern p (a "C4")) (order p))

#f
```
