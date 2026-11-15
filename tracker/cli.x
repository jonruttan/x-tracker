; # x-tracker -- a music tracker on x-lang
;
; ## tracker/cli.x -- the command line
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
;   x -l tracker -- [OPTIONS] [edit] [FILE]   the editor
;   x -l tracker -- [OPTIONS] play FILE       a song played
;   x -l tracker -- list FILE                 the songs of a file
;   x -l tracker -- render FILE -o OUT.wav    a song played once, to a WAV file
;   x -l tracker -- help [WORD]               the help, or the help on WORD
;   x -l tracker -- import FILE -o OUT.xon    a MIDI or SID file read into a song
;
; The options are one declaration to the platform's Opts, which parses
; them and prints the help.  A file is any .xon file of (song ...) forms
; (x/audio/tracker's), with any (wave NAME AMP ...) forms its instruments
; name; --waves reads the waves of another file as well, as a set of
; x-roguelike's keeps them in sounds.xon beside music.xon.

(module tracker/cli)

(import x/sys/opts)
(import x/sys/gc)
(import x/sys/sdl)
(import x/repl/term)
(import x/audio/tracker)
(import x/core/doors int/ int%)
(import tracker/song song-name song-order song-pattern song-patterns song-form pattern-rows)
(import tracker/file file-read file-songs file-waves)
(import tracker/player player-open player-render!)
(import tracker/app app-edit app-play)
(import tracker/config config-load config-get config-problems)
(import tracker/help help-index help-on help-word)
(import tracker/import import-file!)

(def tracker-version "0.1.0")

(def %cl-words (list "edit" "play" "list" "render" "import" "help"))

(def tracker-options
  (Opts declare "x -l tracker --" "[OPTIONS] [edit] [FILE] | play FILE | list FILE | render FILE -o OUT.wav | import FILE -o OUT.xon | help [WORD]"
    "A music tracker: songs of patterns and instruments, edited on the terminal and heard through SDL.\nWith no word, or edit, the editor (? in it lists the keys); play plays a song, list lists a file's songs,\nrender writes a song played once to a WAV file, import reads a MIDI or SID file into a song.\nSettings are read from $X_TRACKER_CONFIG, else ~/.config/x/tracker.xon; :set in the editor lists them."
    (list (Opts arg "-s" "--song" "NAME" "The song to edit or play (the file's first); the name import gives")
          (Opts arg "-w" "--waves" "FILE" "Read the (wave ...) forms of FILE too; again for another")
          (Opts flag "-l" "--loop" "Play the song over and over, until q")
          (Opts arg "-o" "--output" "FILE" "The WAV file render writes, the song file import adds to")
          (Opts arg "-r" "--rows" "N" "Rows a beat import places a MIDI file's notes on, 1-64 (4)")
          (Opts arg "-u" "--tune" "N" "The tune of a SID file import plays (the one it starts with)")
          (Opts arg "-t" "--time" "SECS" "Seconds of a SID tune import plays, 1-3600 (HVSC's length, or 60)")
          (Opts flag "-n" "--no-sound" "Edit without opening the audio")
          (Opts flag "-V" "--version" "Print the version and exit")
          (Opts flag "-h" "--help" "Print this help and exit"))
    (pair (lit help) #f)))

(def %cl-say (fn (_ fd text) (Sys fd-write fd text)))

(def %cl-err-text
  (fn (_ e) (match ((Err err? e) (e msg)) ((str? e) e) (#t "failed"))))

; The (MM:SS) a song lasts played once through at its own tempo.
(def %cl-length
  (fn (_ s)
    (def ms (Tracker row-ms (Tracker make (song-form s ()))))
    (%cl-clock (int/ (* ms (List fold (fn (_ n p) (+ n (pattern-rows (song-pattern s p)))) 0 (song-order s))) 1000))))

; SECS as M:SS.
(def %cl-clock
  (fn (_ secs) (Str8 append (Str8 str (int/ secs 60)) ":" (Str8 pad-left 2 #\0 (Str8 str (int% secs 60))))))

(def %cl-list
  (fn (_ doc)
    (List fold
      (fn (_ status s)
        (def line (guard (e (Str8 append "  " (%cl-err-text e)))
                    (Str8 append "  " (%cl-length s) "  " (Str8 str (List length (song-patterns s))) " patterns  order "
                      (Str8 join " " (song-order s)))))
        (%cl-say 1 (Str8 append (song-name s) line "\n"))
        (Heap collect)
        (if (Str8 starts? "  x-tracker:" line) 1 status))
      0 (file-songs doc))))

; The song named NAME in DOC, its first when NAME is nil, or nil.
(def %cl-song-index
  (fn (_ doc name)
    (if (null? name) (if (null? (file-songs doc)) () 0)
      (List find-index (fn (_ s) (str=? (song-name s) name)) (file-songs doc)))))

; The waves of DOC, then of each -w file, then of each the settings name.
(def %cl-waves
  (fn (_ doc opts cfg)
    (List append (file-waves doc)
      (List flat-map (fn (_ f) (file-waves (file-read f))) (List append (Opts values opts "-w") (config-get cfg (lit waves)))))))

; The settings, each problem the file has written to standard error.
(def %cl-config
  (fn (_)
    (def cfg (config-load))
    (List for-each (fn (_ p) (%cl-say 2 (Str8 append "x-tracker: " p "\n"))) (config-problems cfg))
    cfg))

; The help LOOK finds on WORD (help-on, help-word), or the topics when
; WORD is nil, to standard output.
(def %cl-help
  (fn (_ word look)
    ((fn (_ lines)
       (if (null? lines) (do (%cl-say 2 (Str8 append "x-tracker: no help on " word "; help lists the topics\n")) 1)
         (do (%cl-say 1 (Str8 append (Str8 join "\n" lines) "\n")) 0)))
     (if (null? word) (help-index) (look word)))))

; N, the text an option was given, as a number from LEAST to MOST, or
; DEFAULT when the option was not given; nil when it is no such number.
(def %cl-number
  (fn (_ given least most default)
    (if (null? given) default
      ((fn (_ n) (if (if (null? n) #t (if (< n least) #t (< most n))) () n))
       (guard (e ()) ((prim-ref (lit convert) (lit to)) given (Type named INTEGER) 10))))))

; The file at PATH imported into the -o file: the exit status.
(def %cl-import
  (fn (_ path opts)
    (def out (Opts value opts "-o"))
    (def rows (%cl-number (Opts value opts "-r") 1 64 4))
    (def tune (%cl-number (Opts value opts "-u") 1 256 0))
    ; Without -t a SID tune plays as long as HVSC says it is.
    (def timed (not (null? (Opts value opts "-t"))))
    (def secs (%cl-number (Opts value opts "-t") 1 3600 ()))
    (match
      ((null? out) (do (%cl-say 2 "x-tracker: import needs -o OUT.xon, the song file to add to\n") 2))
      ((null? rows) (do (%cl-say 2 "x-tracker: -r takes rows a beat, 1-64\n") 2))
      ((null? tune) (do (%cl-say 2 "x-tracker: -u takes a tune, 1-256\n") 2))
      ((if timed (null? secs) #f) (do (%cl-say 2 "x-tracker: -t takes seconds, 1-3600\n") 2))
      (#t ((fn (_ s)
             (%cl-say 1 (Str8 append "Imported " (song-name s) " to " out ": " (%cl-length s) "  "
                          (Str8 str (List length (song-patterns s))) " patterns  " (Str8 str (List length (song-order s))) " in the order\n"))
             0)
           (import-file! path out (Opts value opts "-s") rows tune secs
             (fn (_ line) (%cl-say 2 (Str8 append "x-tracker: " line "\n")))))))))

(def %cl-run
  (fn (_ opts)
    (def ops (Opts operands opts))
    (def word (if (null? ops) "edit" (first ops)))
    (def named (List includes? word %cl-words))
    (def files (if named (rest ops) ops))
    (def path (if (null? files) () (first files)))
    (match
      ((str=? word "help") (%cl-help (if (null? files) () (first files)) help-on))
      ((< 1 (List length files)) (do (%cl-say 2 "x-tracker: one file at a time\n") 2))
      ((if (str=? word "edit") #f (null? path)) (do (%cl-say 2 (Str8 append "x-tracker: " word " needs a FILE\n")) 2))
      ((str=? word "list") (%cl-list (file-read path)))
      ((str=? word "import") (%cl-import path opts))
      ((if (str=? word "render") (null? (Opts value opts "-o")) #f)
        (do (%cl-say 2 "x-tracker: render needs -o OUT.wav, the file to write\n") 2))
      (#t
        (do (def doc (if (null? path) () (file-read path)))
            (def i (%cl-song-index doc (Opts value opts "-s")))
            (match
              ((if (str=? word "edit") #f (null? i))
                (do (%cl-say 2 (Str8 append "x-tracker: no song " (if (null? (Opts value opts "-s")) "in the file" (Opts value opts "-s")) "\n")) 1))
              ((str=? word "play")
                (app-play (List ref i (file-songs doc)) (player-open Sdl (%cl-waves doc opts (%cl-config))) (Opts on? opts "-l")))
              ((str=? word "render")
                ((fn (_ out frames)
                   (%cl-say 1 (Str8 append "Rendered " out ": " (%cl-clock (int/ frames 44100)) "\n"))
                   0)
                 (Opts value opts "-o")
                 (player-render! (player-open () (%cl-waves doc opts (%cl-config))) (List ref i (file-songs doc)) (Opts value opts "-o"))))
              (#t
                (do (def cfg (%cl-config))
                    ((fn (_ sound)
                       (app-edit doc path (first sound)
                         (if (if (str=? (rest sound) "") (not (null? (config-problems cfg))) #f)
                           (first (config-problems cfg)) (rest sound))
                         cfg))
                     (if (if (Opts on? opts "-n") #t (not (config-get cfg (lit sound)))) (pair () "")
                       (guard (e (pair () (Str8 append "No sound: " (%cl-err-text e))))
                         (pair (player-open Sdl (%cl-waves doc opts cfg)) ""))))))))))))

; The terminal back on fd 0.  The launcher pipes the program to the
; engine on fd 0 and parks the terminal on fd 3, as x/repl/loop.x
; reclaims it; read before then, fd 0 is the rest of the boot stream.
(def %cl-terminal!
  (fn (_)
    (when (Sys isatty 3)
      (do (Sys dup2 3 0) (Sys close 3)))))

; The command line ARGS run: the exit status.
(def tracker-main
  (fn (_ args)
    (%cl-terminal!)
    (def opts (Opts parse tracker-options args))
    (match
      ((not (null? (Opts unknown opts)))
        (do (%cl-say 2 (Str8 append "x-tracker: unknown option " (Opts unknown opts) "\n" (Opts usage tracker-options))) 2))
      ((Opts on? opts "-h")
        ((fn (_ ops)
           (if (if (null? ops) #f (List includes? (first ops) %cl-words))
             (%cl-help (first ops) help-word)
             (do (%cl-say 1 (Str8 append (Opts usage tracker-options) "help lists the topics of the help; help WORD, or WORD -h, the help on WORD\n")) 0)))
         (Opts operands opts)))
      ((Opts on? opts "-V") (do (%cl-say 1 (Str8 append "x-tracker " tracker-version "\n")) 0))
      (#t (guard (e (do (%cl-say 2 (Str8 append (%cl-err-text e) "\n")) 1)) (%cl-run opts))))))

(provide tracker/cli tracker-version tracker-options tracker-main)
