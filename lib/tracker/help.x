; # x-tracker -- a music tracker on x-lang
;
; ## tracker/help.x -- the help, one source for the editor and the command line
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; Everything the help says is in the tables here: the keys, the commands,
; a cell's effects, a song's items, an instrument's props, the settings
; and the command line's words.  A topic is lines made from them; ? in
; the editor pages through the topics, :help WORD shows a topic or every
; entry named WORD, and `x -l tracker -- help [WORD]` prints the same.
;
; An entry is (NAME USAGE LINE ...): what it is looked up by, how it is
; written, and what it does.

(module tracker/help)

; --- the tables ----------------------------------------------------------------

; The keys, (ACTIONS KEYS TEXT), grouped under headings (a string): ACTIONS
; the names :set key binds them by (tracker/config), nil for a key that
; cannot be bound.
(def %hp-keys
  (list "Pages"
        (list () "F1" "this help")
        (list () "F2" "the pattern editor")
        (list () "F3" "the samples: the WAV files the file keeps as waves")
        (list () "F4" "the instruments, and an instrument's envelope drawn and edited")
        (list () "F11" "the order list")
        (list () "F12" "the song's settings")
        (list () "F9" "open a file, as :open")
        (list () "F10 ctrl-s" "write the file, as :w")
        (list () "Escape" "on a page, back to the pattern")
        "Notes"
        (list () "z s x d c v g b h n j m ," "a note, C to C, in the octave; heard as it is typed")
        (list () "q 2 w 3 e r 5 t 6 y 7 u i" "a note, the octave above")
        (list (list (lit hold)) ". or Delete" "hold: what sounds carries on")
        (list (list (lit let-go)) "- or `" "let go: what sounds fades over its release")
        (list () "1" "cut: what sounds stops there, /c0")
        (list (list (lit octave-down) (lit octave-up)) "< >" "the octave notes are typed in, down, up")
        (list (list (lit step-down) (lit step-up)) "{ }" "the step: rows the cursor moves after a note")
        (list () "4 8" "hear the cell, the whole row, and move down")
        "Moving"
        (list (list (lit up) (lit down)) "up down" "a row up, down")
        (list (list (lit left) (lit right)) "left right" "the cell's note, instrument, volume and effect columns, then the next channel's")
        (list () "Alt-left Alt-right" "a channel left, right")
        (list (list (lit next-channel)) "Tab Shift-Tab" "the next channel's note, the one before's")
        (list (list (lit page-up) (lit page-down)) "PgUp PgDn" "sixteen rows up, down")
        (list (list (lit top) (lit bottom)) "Home End  Ctrl-PgUp Ctrl-PgDn" "the first row, the last")
        (list (list (lit previous) (lit next)) "[ ]" "the pattern before, after in the order")
        "Editing"
        (list () "digits" "in the instrument column, the channel's instrument by its number (F4 lists them);"
              "  in the volume column, the note's gain in percent; . there clears it")
        (list () "a letter" "in the effect column, an effect typed after it (:help effects)")
        (list (list (lit edit-cell)) "Enter" "edit the cell's text: NOTE[:GAIN][/EFFECT...]")
        (list (list (lit edit-instrument)) "E" "edit the channel's instrument, its form on one line")
        (list () "Insert Shift-Delete" "insert a row in the channel, delete one")
        (list (list (lit insert-row) (lit delete-row)) "I D  Alt-Insert Alt-Delete" "insert a row, delete one, in every channel")
        (list (list (lit channel-left) (lit channel-right)) "( )" "move the channel left, right")
        (list (list (lit order)) "O" "edit the order in place (:help order)")
        (list (list (lit undo) (lit redo)) "U R  ctrl-z" "undo, redo")
        "Blocks"
        (list () "Alt-B Alt-E" "mark where the block begins, where it ends")
        (list () "Shift-arrows" "mark a block from the cursor as it moves")
        (list () "Alt-L Alt-D" "mark the channel's column, then the pattern's; mark rows a beat at a time")
        (list () "Alt-U" "unmark the block")
        (list (list (lit mark)) "V" "mark a block from the cursor; move to its other corner")
        (list (list (lit copy) (lit cut) (lit paste)) "Y X P" "copy, cut, paste the block, or the cell")
        (list () "Alt-C Alt-Z" "copy the block, cut it")
        (list () "Alt-P Alt-O Alt-M" "paste, the rows pushed down; paste over; paste into the holds only")
        (list () "Alt-Q Alt-A" "the block a semitone up, down; with Shift an octave")
        (list () "Alt-K" "the gains slid from the block's first row to its last")
        (list () "Alt-X" "the first effect's numbers slid from the block's first row to its last")
        (list () "Alt-W" "the block's gains cleared")
        (list () "Alt-V Alt-J" "the block's gains set, :gain PCT; taken up or down, :amplify PCT")
        (list () "Alt-S" "the channel played by another instrument, :channel-instrument")
        (list () "Alt-F Alt-G" "the block stretched to twice its rows, squeezed to half")
        (list () "Delete" "with a block marked, clear it")
        "Playing"
        (list (list (lit play)) "Space" "play the song from the pattern edited, or stop")
        (list (list (lit play-pattern)) "p" "play the pattern edited over and over, or stop")
        (list () "F5 F6 Shift-F6 F7 F8" "play the song; the pattern; the song from the pattern; from the cursor's row; stop")
        (list (list (lit play-here)) "G" "play the song from the cursor's row")
        (list (list (lit loop)) "L" "loop rows: L on the first, L on the last; L again stops")
        (list (list (lit mute-channel) (lit solo-channel)) "M S  Alt-F9 Alt-F10" "mute the channel, solo it; again to undo")
        (list (list (lit mute-instrument) (lit solo-instrument)) "H A" "mute the channel's instrument, solo it")
        (list (list (lit tension-down) (lit tension-up)) "; '" "the tension down, up: the tension layer and tempo")
        (list (list (lit pace-down) (lit pace-up)) "_ +" "the pace down, up: the whole song slower, faster")
        (list (list (lit volume-down) (lit volume-up)) "9 0" "the volume down, up")
        (list (list (lit follow)) "F" "follow the playing: the pattern and row heard shown")
        "The editor"
        (list (list (lit command)) ":" "type a command (:help commands)")
        (list (list (lit help)) "?" "this help: n, p the next and previous topic")
        (list (list (lit quit)) "ctrl-c  ctrl-q" "quit, as :q")))

; The commands, each an entry, grouped under headings.
(def %hp-commands
  (list "The file"
        (list "w" ":w [FILE]" "write the file, or to FILE; a .bak of it is kept first (:set backup)")
        (list "q" ":q" "quit; refused once while there are changes not written")
        (list "q!" ":q!" "quit, the changes lost")
        (list "wq" ":wq [FILE]  :x [FILE]" "write, then quit")
        (list "x" ":x [FILE]" "write, then quit, as :wq")
        (list "open" ":open FILE" "edit FILE in place of this file; refused once while there are changes not written")
        "Songs"
        (list "song" ":song [NAME]" "edit the song NAME, made if new; alone, pick one from a list")
        (list "rename" ":rename NAME" "rename the song")
        (list "copy-song" ":copy-song NAME" "copy the song as NAME, and edit the copy")
        (list "drop-song" ":drop-song" "drop the song from the file; U brings it back")
        (list "bpm" ":bpm N" "beats a minute, 1-999")
        (list "rows" ":rows N" "rows a beat, 1-999: every Nth row is drawn as a beat")
        (list "ticks" ":ticks N" "ticks a row, 1-999: the clock a cell's effects run on")
        (list "tension-bpm" ":tension-bpm N" "beats a minute added at full tension, 0-999")
        (list "order" ":order NAME ..." "the patterns in the order they play; O edits it in place")
        "Patterns and channels"
        (list "pattern" ":pattern NAME" "edit the pattern NAME, made if new with the channels of this one")
        (list "patterns" ":patterns" "list the patterns: rows, channels, times played")
        (list "copy-pattern" ":copy-pattern NEW" "copy the pattern as NEW, and edit the copy")
        (list "rename-pattern" ":rename-pattern NEW" "rename the pattern, in the order too")
        (list "drop-pattern" ":drop-pattern [NAME]" "drop the pattern, or NAME, from the song and the order")
        (list "len" ":len N" "the pattern's rows, 1-256: cut, or held to the end")
        (list "channel" ":channel INSTRUMENT" "add a channel played by INSTRUMENT")
        (list "drop" ":drop" "drop the cursor's channel; a pattern keeps one")
        (list "channel-instrument" ":channel-instrument NAME" "the cursor's channel played by instrument NAME")
        (list "transpose" ":transpose N" "the block marked, or the cell, N semitones up or down")
        (list "gain" ":gain PCT" "the block marked, or the cell, at PCT percent, 0-400")
        (list "amplify" ":amplify PCT" "the gains of the block marked, or the cell, taken to PCT percent of themselves")
        "Instruments, effects and waves"
        (list "instrument" ":instrument NAME [PROP ...]" "make or change an instrument; NAME alone opens its form to edit"
              "  (:help instruments lists the props)")
        (list "instruments" ":instruments" "list the instruments and the patterns each plays in")
        (list "copy-instrument" ":copy-instrument NAME NEW" "copy instrument NAME as NEW")
        (list "rename-instrument" ":rename-instrument NAME NEW" "rename an instrument, in every channel too")
        (list "drop-instrument" ":drop-instrument NAME" "drop an instrument no channel plays")
        (list "effects" ":effects" "list the effects over the whole mix, in the order they run")
        (list "effect" ":effect (NAME N ...)" "add an effect over the mix (:help song lists them)"
              "  :effect K edits the Kth, :effect K (NAME N ...) replaces it, :effect drop K drops it")
        (list "waves" ":waves  :waves keep" "list the waves the songs name and where each comes from;"
              "  keep copies the ones borrowed from -w files into this file")
        (list "wave" ":wave NAME [AMP ...]" "show a wave, or make or change it: the strengths of its harmonics")
        (list "sample" ":sample NAME FILE [ROOT] [START END]" "keep the WAV file FILE as the wave NAME: heard at ROOT, looped from START to END"
              "  (sample frames); FILE named from the directory of the file edited")
        "Playing"
        (list "tension" ":tension N" "the tension heard, 0-100: the tension layer in, the calm out, the tempo up")
        (list "pace" ":pace N" "the pace, 10-400 percent: the whole song slower or faster")
        (list "volume" ":volume N" "the volume, 0-100")
        (list "mute" ":mute [INSTRUMENT]" "mute an instrument; alone, say what is muted and soloed")
        (list "solo" ":solo [INSTRUMENT]" "hear only an instrument; alone, say what is muted and soloed")
        (list "unmute" ":unmute" "hear every channel and instrument again")
        (list "loop" ":loop [FROM TO]" "loop rows FROM to TO of the pattern; alone, the whole pattern")
        (list "render" ":render FILE" "the song played once, to a WAV file")
        "The editor"
        (list "octave" ":octave N" "the octave notes are typed in, 0-8")
        (list "step" ":step N" "rows the cursor moves after a note, 0-64")
        (list "set" ":set [NAME VALUE ...]" "change a setting for this session; alone, list them (:help settings)")
        (list "help" ":help [WORD]" "the help on a topic, or on every command, effect, prop or setting named WORD")))

; A cell's effects, after a /: an entry each, named by its letter.
(def %hp-effects
  (list (list "a" "/aX,Y,..." "arpeggio: the note, then X, then Y ... semitones up, a tick each")
        (list "v" "/vD,P" "vibrato: D cents either way, a cycle every P ticks")
        (list "s" "/sC" "slide: C cents (below 0 down) by the next slide or the note's end, then held")
        (list "p" "/pN" "portamento: from the channel's last note to this one over N ticks")
        (list "t" "/tD,P" "tremolo: D percent down and back every P ticks")
        (list "f" "/fP" "fade: to P percent by the next fade or the note's end")
        (list "l" "/lP" "low-pass: to P percent of the instrument's cut by the next l or the note's end")
        (list "w" "/wP" "width: a pulse's to P percent of its cycle by the next w or the note's end")
        (list "o" "/oH" "cut-off: the resonant filter's to H hertz by the next o or the note's end")
        (list "x" "/xC" "ring: the note rung by a modulator C cents from its pitch")
        (list "y" "/yC" "sync: the note hard-synced to a modulator C cents from its pitch")
        (list "c" "/cN" "cut: let go N ticks into the row")
        (list "d" "/dN" "delay: start N ticks into the row, on the note's own cell")
        (list "r" "/rN" "retrigger: start again every N ticks")))

; A song's items: its props and the effects over its mix.
(def %hp-song
  (list (list "bpm" "(bpm N)" "beats a minute (90)")
        (list "rows" "(rows N)" "rows a beat (4)")
        (list "ticks" "(ticks N)" "ticks a row, the clock a cell's effects run on (6)")
        (list "tension-bpm" "(tension-bpm N)" "beats a minute added at full tension (0)")
        (list "echo" "(echo MS FB WET)" "the mix delayed MS, FB percent fed back, WET percent added")
        (list "reverb" "(reverb SIZE DECAY WET)" "a room SIZE percent of a middling one, DECAY percent fed back")
        (list "phase" "(phase LEAST-MS MOST-MS PERIOD-MS FB WET)" "a short delay swept: a phaser at a ms or two, a flanger at more")
        (list "chorus" "(chorus VOICES MS DEPTH-MS PERIOD-MS WET)" "1-4 copies of the mix, each delayed and swept")
        (list "drive" "(drive GAIN WET)" "the mix taken up GAIN percent and rounded off: saturation")
        (list "crush" "(crush BITS HZ)" "BITS of each sample's 16 kept, held HZ times a second")
        (list "sweep" "(sweep LOW-HZ HIGH-HZ PERIOD-MS RES)" "a resonant low-pass swept up and back: an auto-wah")
        (list "limit" "(limit CEILING RELEASE-MS)" "the mix held under CEILING percent of full scale")
        (list "instrument" "(instrument NAME PROP ...)" "an instrument (:help instruments)")
        (list "pattern" "(pattern NAME (INSTRUMENT \"CELLS\") ...)" "a pattern: a channel each, a cell a row")
        (list "order" "(order NAME ...)" "the patterns in the order they play")))

; An instrument's props, and a voice's: what x/audio/mixer plays.
(def %hp-props
  (list (list "wave" "(wave NAME)" "the wave a voice reads: one of the mixer's own (:help waves), or one a (wave ...) form makes")
        (list "env" "(env (MS PCT) ...)" "the level over time, straight between points; ends at the last")
        (list "release" "(release MS)" "how long a note fades once let go (200)")
        (list "gain" "(gain PCT)" "the voice's level")
        (list "pan" "(pan -100..100)" "left to right")
        (list "cut" "(cut PCT)" "a low-pass, as a percentage of the pitch's range")
        (list "filter" "(filter (MS PCT) ...)" "the low-pass moving over time")
        (list "width" "(width (MS PCT) ...)" "the wave less itself PCT of a cycle on: a saw's pulse, swept as it moves")
        (list "cutoff" "(cutoff (MS HZ) ...)" "a resonant filter after the low-pass, its cut-off in hertz over time")
        (list "res" "(res PCT)" "the resonant filter's resonance, 0-100 (0)")
        (list "pass" "(pass MODE ...)" "what the resonant filter lets through: low, band, high (low)")
        (list "ring" "(ring CENTS)" "rung by a modulator CENTS from the pitch: on a triangle, a ring modulator")
        (list "sync" "(sync CENTS)" "hard-synced to a modulator CENTS from the pitch")
        (list "detune" "(detune CENTS)" "the voice moved off its pitch")
        (list "note" "(note \"C4\")  (hz N)" "a pitch of its own: a cell's note only starts it, as a drum")
        (list "hz" "(hz N)" "a pitch of its own, in hertz")
        (list "slide" "(slide PITCH)" "the pitch slid to PITCH over the envelope")
        (list "bend" "(bend (MS CENTS) ...)" "the pitch moved over time")
        (list "at" "(at MS)" "the voice starts MS after the note")
        (list "layer" "(layer calm|tension)" "heard as the tension falls, or as it rises")
        (list "voice" "(voice PROP ...)" "a voice of its own over the instrument's other props; any number")))

; The settings, as the file (tracker/config) and :set take them.
(def %hp-settings
  (list (list "octave" "(octave N)" "the octave notes are typed in at the start, 0-8 (4)")
        (list "step" "(step N)" "rows the cursor moves after a note, 0-64 (1)")
        (list "follow" "(follow on|off)" "follow the playing (on)")
        (list "backup" "(backup on|off)" "keep FILE.bak of a file before its first :w (on)")
        (list "undo" "(undo N)" "how many changes are kept to undo (200)")
        (list "sound" "(sound on|off)" "open the audio as the editor starts (on)")
        (list "waves" "(waves FILE ...)" "files whose (wave ...) forms are read, as -w")
        (list "colour" "(colour NAME ATTRIBUTES FG BG)" "how NAME is drawn: title empty heading beat off instrument volume"
              "  effect cursor playing block; ATTRIBUTES a list of bold dim italic underline reverse"
              "  strike, FG and BG 0-255, a name (red, bright-blue ...) or ()")
        (list "key" "(key ACTION KEY ...)" "bind an action to other keys (:help keys names them);"
              "  (key ACTION) gives it back its own")))

; The command line's words.
(def %hp-words
  (list (list "edit" "x -l tracker -- [OPTIONS] [edit] [FILE]" "the editor; with no FILE, a new song to write with :w FILE"
              "  -s NAME the song to edit, -w FILE waves to read, -n no sound")
        (list "play" "x -l tracker -- [OPTIONS] play FILE" "play a song, the pattern heard written to standard error; q stops"
              "  -s NAME the song (the file's first), -l loop it, -w FILE waves to read")
        (list "list" "x -l tracker -- list FILE" "each song of FILE: how long it lasts, its patterns and its order")
        (list "render" "x -l tracker -- render FILE -o OUT.wav" "a song played once, to a WAV file"
              "  -s NAME the song (the file's first), -w FILE waves to read")
        (list "import" "x -l tracker -- import FILE -o OUT.xon" "a MIDI (.mid) or SID (.sid) file read into a song, added to OUT.xon"
              "  -s NAME the song's name (the file's); MIDI: -r N rows a beat (4);"
              "  SID: -u N the tune (its first), -t SECS how long it is played (HVSC's length, or 60)")
        (list "help" "x -l tracker -- help [WORD]" "this help: the topics, a topic, or every entry named WORD")))

; --- the topics ----------------------------------------------------------------

(def %hp-pad (fn (_ w s) (if (< (Str8 length s) w) (Str8 pad-right w #\space s) s)))

; ENTRIES as lines, headings as they are, each entry's usage padded to W
; and the lines after its first under it.
(def %hp-entry-lines
  (fn (_ entries w)
    (List flat-map
      (fn (_ e)
        (if (str? e) (list e)
          (pair (Str8 append "  " (%hp-pad w (List ref 1 e)) "  " (List ref 2 e)) (List map (fn (_ c) (Str8 append "  " (%hp-pad w "") "  " (Str8 trim-left c))) (List drop 3 e)))))
      entries)))

(def %hp-key-lines
  (fn (_)
    (List append
      (List flat-map (fn (_ e) (if (str? e) (list e) (list (Str8 append "  " (%hp-pad 26 (List ref 1 e)) "  " (List ref 2 e))))) %hp-keys)
      (list "" "  :set key ACTION KEY binds a key; :set lists the actions and their keys."))))

(def %hp-cell-lines
  (list "A cell is a row of a channel:"
        "  C4  F#3  Bb2       a note: starts it, the last one ending"
        "  C4:60              the note at 60 percent"
        "  .                  hold: what sounds carries on"
        "  -                  let go: what sounds fades over its release"
        "Any cell can carry effects, / then a letter and its numbers:"
        "  C4/v20,4           C4 with a vibrato"
        "  ./s-200            a slide down from this row, the note held"
        "A note's effects hold until the next of their letter, or the note's end."
        "Times are ticks, a row over the song's (ticks N).  :help effects lists them."))

(def %hp-order-lines
  (list "O edits the order in place, the place picked shown <so>:"
        "  left right        pick a place"
        "  up down           change its pattern"
        "  i                 put a copy of it after it"
        "  d or Delete       drop it"
        "  [ ]               move it earlier, later"
        "  Enter             edit its pattern, and stop"
        "  Escape or O       stop"
        ":order NAME ... sets the whole order at once."))

(def %hp-wave-lines
  (list "A wave is the strengths of its harmonics, the fundamental first:"
        "  (wave hollow 6 0 2 0 1)     odd harmonics: hollow, like a clarinet"
        "  (wave reed 6 4 3 2 1 1)     every harmonic, falling: bright, like a saw"
        "  (wave glass 5 0 0 2 0 0 0 1)"
        "Or the points it is drawn through, (POSITION LEVEL), straight lines between:"
        "  (wave stair (0 100) (1 100) (1 0) (2 0) (2 -100) (3 -100))"
        "The mixer's own: sine, square, triangle, saw, inverse-saw, pulse, noise, metal."
        "pulse is the saw at (width (0 50)); give it a width of its own, or sweep one."
        "An instrument names a wave with (wave NAME)."
        "A file keeps its waves as (wave ...) forms beside its songs; -w FILE reads another's."
        ":waves lists them, :waves keep copies the borrowed in, :wave NAME AMP ... makes one."))

; The topics, (NAME SUMMARY LINES-FN).
(def %hp-topics
  (list (list "keys" "every key, and the action :set key binds it by" (fn (_) (%hp-key-lines)))
        (list "commands" "every : command" (fn (_) (%hp-entry-lines %hp-commands 30)))
        (list "cells" "what a cell holds: a note, a gain, effects" (fn (_) %hp-cell-lines))
        (list "effects" "a cell's effects, after /" (fn (_) (%hp-entry-lines %hp-effects 12)))
        (list "song" "a song's props and the effects over its mix" (fn (_) (%hp-entry-lines %hp-song 44)))
        (list "instruments" "an instrument's props, and its voices'" (fn (_) (%hp-entry-lines %hp-props 24)))
        (list "waves" "the mixer's own waves, harmonics, and where waves are kept" (fn (_) %hp-wave-lines))
        (list "order" "the order, edited in place with O" (fn (_) %hp-order-lines))
        (list "settings" "the settings file and :set" (fn (_)
                                                        (List append
                                                          (list "The file is $X_TRACKER_CONFIG, else $XDG_CONFIG_HOME/x/tracker.xon,"
                                                                "else ~/.config/x/tracker.xon: a form a setting.  :set NAME VALUE ... is the same.")
                                                          (%hp-entry-lines %hp-settings 32))))
        (list "cli" "the command line's words and options" (fn (_) (%hp-entry-lines %hp-words 40)))))

(def help-topics (fn (_) (List map first %hp-topics)))

; The lines of topic NAME, its summary first, or nil.
(def help-topic
  (fn (_ name)
    ((fn (_ t) (if (null? t) () (pair (Str8 append (first t) ": " (List ref 1 t)) ((List ref 2 t)))))
     (List find (fn (_ t) (str=? (first t) name)) %hp-topics))))

; The index: each topic and what it is.
(def help-index
  (fn (_)
    (pair "Help: :help TOPIC, or :help WORD for every command, effect, prop or setting named WORD"
      (List map (fn (_ t) (Str8 append "  " (%hp-pad 12 (first t)) (List ref 1 t))) %hp-topics))))

(def %hp-tables
  (list (pair "command" %hp-commands) (pair "cell effect" %hp-effects) (pair "song item" %hp-song)
        (pair "instrument prop" %hp-props) (pair "setting" %hp-settings) (pair "word" %hp-words)))

; The entries of TABLES, (WHAT . ENTRIES) each, named NAME, as lines.
(def %hp-entries
  (fn (_ tables name)
    (List flat-map
      (fn (_ tb)
        (List flat-map
          (fn (_ e) (if (if (str? e) #f (str=? (first e) name))
                      (pair (Str8 append (first tb) "  " (List ref 1 e)) (pair (Str8 append "  " (List ref 2 e)) (List drop 3 e)))
                      ()))
          (rest tb)))
      tables)))

; The lines of help on WORD: the topic it names, or every entry named
; it, a command's with or without its colon, an effect's with or without
; its slash; nil when there is none.
(def help-on
  (fn (_ word)
    (def bare (if (if (< 1 (Str8 length word)) (List includes? (Str8 sub 0 1 word) (list ":" "/")) #f)
                (Str8 sub 1 (- (Str8 length word) 1) word) word))
    (def topic (help-topic bare))
    (if (null? topic) (%hp-entries %hp-tables bare) topic)))

; The lines of help on the command line's word WORD, or nil.
(def help-word (fn (_ word) (%hp-entries (list (pair "word" %hp-words)) word)))

; The actions the keys table names, for a check that it names them all.
(def help-key-actions
  (fn (_) (List flat-map (fn (_ e) (if (str? e) () (first e))) %hp-keys)))

; The commands the help has an entry for.
(def help-commands
  (fn (_) (List map first (List filter (fn (_ e) (not (str? e))) %hp-commands))))

(provide tracker/help help-topics help-topic help-index help-on help-word help-key-actions help-commands)
