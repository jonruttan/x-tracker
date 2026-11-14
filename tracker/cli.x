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
(import tracker/player player-open)
(import tracker/app app-edit app-play)

(def tracker-version "0.1.0")

(def tracker-options
  (Opts declare "x -l tracker --" "[OPTIONS] [edit] [FILE] | play FILE | list FILE"
    "A music tracker: songs of patterns and instruments, edited on the terminal and heard through SDL.\nWith no word, or edit, the editor (? in it lists the keys); play plays a song, list lists a file's songs."
    (list (Opts arg "-s" "--song" "NAME" "The song to edit or play (the file's first)")
          (Opts arg "-w" "--waves" "FILE" "Read the (wave ...) forms of FILE too; again for another")
          (Opts flag "-l" "--loop" "Play the song over and over, until q")
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
    (def secs (int/ (* ms (List fold (fn (_ n p) (+ n (pattern-rows (song-pattern s p)))) 0 (song-order s))) 1000))
    (Str8 append (Str8 str (int/ secs 60)) ":" (Str8 pad-left 2 #\0 (Str8 str (int% secs 60))))))

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

(def %cl-waves
  (fn (_ doc opts)
    (List append (file-waves doc) (List flat-map (fn (_ f) (file-waves (file-read f))) (Opts values opts "-w")))))

(def %cl-run
  (fn (_ opts)
    (def ops (Opts operands opts))
    (def word (if (null? ops) "edit" (first ops)))
    (def named (List includes? word (list "edit" "play" "list")))
    (def files (if named (rest ops) ops))
    (def path (if (null? files) () (first files)))
    (match
      ((< 1 (List length files)) (do (%cl-say 2 "x-tracker: one file at a time\n") 2))
      ((if (str=? word "edit") #f (null? path)) (do (%cl-say 2 (Str8 append "x-tracker: " word " needs a FILE\n")) 2))
      ((str=? word "list") (%cl-list (file-read path)))
      (#t
        (do (def doc (if (null? path) () (file-read path)))
            (def i (%cl-song-index doc (Opts value opts "-s")))
            (match
              ((str=? word "play")
                (if (null? i) (do (%cl-say 2 (Str8 append "x-tracker: no song " (if (null? (Opts value opts "-s")) "in the file" (Opts value opts "-s")) "\n")) 1)
                  (app-play (List ref i (file-songs doc)) (player-open Sdl (%cl-waves doc opts)) (Opts on? opts "-l"))))
              (#t
                ((fn (_ sound)
                   (app-edit doc path (first sound) (rest sound)))
                 (if (Opts on? opts "-n") (pair () "")
                   (guard (e (pair () (Str8 append "No sound: " (%cl-err-text e))))
                     (pair (player-open Sdl (%cl-waves doc opts)) "")))))))))))

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
      ((Opts on? opts "-h") (do (%cl-say 1 (Opts usage tracker-options)) 0))
      ((Opts on? opts "-V") (do (%cl-say 1 (Str8 append "x-tracker " tracker-version "\n")) 0))
      (#t (guard (e (do (%cl-say 2 (Str8 append (%cl-err-text e) "\n")) 1)) (%cl-run opts))))))

(provide tracker/cli tracker-version tracker-options tracker-main)
