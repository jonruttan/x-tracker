; # x-tracker -- a music tracker on x-lang
;
; ## tracker/app.x -- the editor on the terminal, and a song played there
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; The editor takes the terminal as x-chess does: raw, on the alternate
; screen, all given back as it was on the way out.  While a song plays
; the loop comes round every 20 ms to keep its stream fed and to show the
; row being heard; while none does, every quarter second to keep the
; screen the terminal's size.  x collects its heap only when asked: after
; each key, and every so many rounds while a song plays.

(module tracker/app)

(import x/type/vector)
(import x/sys/posix)
(import x/sys/gc)
(import x/repl/term)
(import x/tui/screen)
(import tracker/edit edit-make edit-quit? edit-player edit-message! edit-feed! edit-tick! edit-key! edit-draw!)
(import tracker/player player-playing? player-start! player-pump! player-place player-over? player-queued player-close)
(import tracker/song song-name song-order)

(def %ap-esc (fn (_ text) (Str8 append "\x1b" text)))

; Rounds of the loop between collects while a song plays.
(def %ap-collect-rounds 50)

; A byte reader for Term key: bytes read sixty-four at a time and handed
; out one by one; asked anything, whether any are in hand.  After an
; Escape with none in hand it waits thirty milliseconds for more, and
; answers nil when none come, which the decoder takes as a bare Escape
; rather than the start of a sequence.
(def %ap-reader
  (fn (_)
    (def box (Vector of () #f))
    (def waiting? (fn (_) (not (null? (Sys poll (list (pair 0 (list (lit in)))) 30)))))
    (fn (self . ask)
      (if (not (null? ask)) (not (null? (Vector ref 0 box)))
        (do (when (if (null? (Vector ref 0 box)) (if (Vector ref 1 box) (waiting?) #t) #f)
              (Vector set! 0 (Sys fd-read 0 64) box))
            (def b (if (null? (Vector ref 0 box)) () (first (Vector ref 0 box))))
            (unless (null? b) (Vector set! 0 (rest (Vector ref 0 box)) box))
            (Vector set! 1 (if (null? b) #f (= b 27)) box)
            b)))))

(def %ap-waiting?
  (fn (_ reader ms)
    (if (reader (lit ask)) #t (not (null? (Sys poll (list (pair 0 (list (lit in)))) ms))))))

; The screen drawn and sent, the stream topped up first: the drawing
; keeps the loop from coming round, and the music plays on what is
; queued meanwhile.
(def %ap-show!
  (fn (_ st screen)
    (edit-feed! st)
    (edit-draw! st screen)
    (Term emit 1 (Screen render screen))))

; The heap collected, the stream topped up first, for the same reason.
(def %ap-collect!
  (fn (_ st)
    (edit-feed! st)
    (Heap collect)))

(def %ap-playing?
  (fn (_ st) (if (null? (edit-player st)) #f (player-playing? (edit-player st)))))

; The screen kept the terminal's size.
(def %ap-resize!
  (fn (_ st screen)
    ((fn (_ size)
       (unless (if (= (first size) (Screen cols screen)) (= (rest size) (Screen rows screen)) #f)
         (do (Screen resize screen (rest size) (first size)) (%ap-show! st screen))))
     (Term window 0))))

(def %ap-loop
  (fn (self st screen reader rounds)
    (match
      ((edit-quit? st) ())
      ((%ap-waiting? reader (if (%ap-playing? st) 20 250))
        ((fn (_ key)
           (if (null? key) ()
             (do (if (eq? key (lit clear)) (Screen repaint screen) (edit-key! st key))
                 (edit-tick! st)
                 (%ap-show! st screen)
                 (%ap-collect! st)
                 (self st screen reader 0))))
         (Term key reader)))
      (#t (do (when (edit-tick! st) (%ap-show! st screen))
              (%ap-resize! st screen)
              (if (< rounds %ap-collect-rounds) (self st screen reader (+ rounds 1))
                (do (%ap-collect! st) (self st screen reader 0))))))))

; Edit DOC, read from PATH, on the terminal, heard through PLAYER (nil
; for none); MSG shown first.  Answers the exit status.
(def app-edit
  (fn (_ doc path player msg)
    (def size (Term window 0))
    (def st (edit-make doc path player))
    (edit-message! st msg)
    (def screen (Screen make (rest size) (first size)))
    (def token (Term raw! 0))
    (Term emit 1 (Str8 append (%ap-esc "[?1049h") (%ap-esc "[?25l")))
    (def failed
      (guard (e e)
        (do (%ap-show! st screen)
            (%ap-loop st screen (%ap-reader) 0)
            ())))
    (Term emit 1 (Str8 append (%ap-esc "[0m") (%ap-esc "[?25h") (%ap-esc "[?1049l")))
    (Term restore! 0 token)
    (unless (null? player) (player-close player))
    (if (null? failed) 0
      (do (Sys fd-write 2 (Str8 append "x-tracker: " (if (Err err? failed) (failed msg) "failed") "\n")) 1))))

; --- playing without the editor ------------------------------------------------

; Whether a key that stops the playing came: q, Escape or ctrl-c.  On a
; terminal it waits up to MS for one; elsewhere it only waits.
(def %ap-stop-key?
  (fn (_ tty ms)
    (if (not tty) (do (Sys poll () ms) #f)
      (if (null? (Sys poll (list (pair 0 (list (lit in)))) ms)) #f
        ((fn (_ b) (if (null? b) #t (List includes? (first b) (list 113 3 27)))) (Sys fd-read 0 1))))))

; S played through PLAYER from the start of its order: once through and
; rung out or, LOOP, over and over, until q, Escape or ctrl-c.  Each
; pattern heard is written to standard error as it comes.  Answers the
; exit status.
(def app-play
  (fn (_ s player loop)
    (def tty (Term tty? 0))
    (def token (if tty (Term raw! 0) ()))
    (def order (song-order s))
    (def say (fn (_ at)
               (Sys fd-write 2 (Str8 append "\r" (song-name s) ": " (Str8 str (+ 1 at)) "/" (Str8 str (List length order))
                                 " " (List ref at order) "        "))))
    (def failed
      (guard (e e)
        (do (player-start! player s (if loop (lit song) (lit once)) 0 ())
            ((fn (self last rounds)
               (match
                 ((player-over? player)
                   (unless (if (= 0 (player-queued player)) #t (%ap-stop-key? tty 20)) (self last rounds)))
                 (#t (do (player-pump! player)
                         (def at (first (player-place player)))
                         (unless (= at last) (say at))
                         (unless (%ap-stop-key? tty 20)
                           (if (< rounds %ap-collect-rounds) (self at (+ rounds 1)) (do (Heap collect) (self at 0))))))))
             -1 0)
            ())))
    (Sys fd-write 2 "\n")
    (unless (null? token) (Term restore! 0 token))
    (player-close player)
    (if (null? failed) 0
      (do (Sys fd-write 2 (Str8 append "x-tracker: " (if (Err err? failed) (failed msg) "failed") "\n")) 1))))

(provide tracker/app app-edit app-play)
