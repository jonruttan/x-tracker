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
; screen the terminal's size.  x collects its heap only when asked: in
; the first quiet round after keys, after each redraw while a song plays,
; and every so many rounds between; a collect costs about as much as a
; drawing, so it waits until no key does.  Keys already waiting when one
; is taken are taken too before the screen is drawn.  Once the
; first screen is drawn, x/tui/screen's cell loops are compiled
; (x/tool/fn-compile), where the engine has a JIT: about a second, before
; the first key is read.

(module tracker/app)

(import x/type/vector)
(import x/sys/posix)
(import x/sys/gc)
(import x/repl/term)
(import x/tui/screen)
(import x/tool/fn-compile compile-module!)
(import tracker/keys keys-read)
(import tracker/state edit-quit? edit-player edit-message!)
(import tracker/edit edit-make edit-feed! edit-settle! edit-tick! edit-key!)
(import tracker/draw edit-draw!)
(import tracker/player player-playing? player-start! player-pump! player-place player-over? player-queued player-close)
(import tracker/song song-name song-order)

(def %ap-esc (fn (_ text) (Str8 append "\x1b" text)))

; Rounds of the loop between collects while a song plays.
(def %ap-collect-rounds 50)

; A byte reader for Term key: bytes read sixty-four at a time and handed
; out one by one.  After an Escape with none in hand it waits thirty
; milliseconds for more, and answers nil when none come, which the
; decoder takes as a bare Escape rather than the start of a sequence.
; Asked (lit wait) and MS, whether a byte is in hand or comes within MS.
(def %ap-reader
  (fn (_)
    (def box (Vector of () #f))
    (def poll? (fn (_ ms) (not (null? (Sys poll (list (pair 0 (list (lit in)))) ms)))))
    (fn (self . ask)
      (if (not (null? ask)) (if (null? (Vector ref 0 box)) (poll? (List ref 1 ask)) #t)
        (do (when (if (null? (Vector ref 0 box)) (if (Vector ref 1 box) (poll? 30) #t) #f)
              (Vector set! 0 (Sys fd-read 0 64) box))
            (def b (if (null? (Vector ref 0 box)) () (first (Vector ref 0 box))))
            (unless (null? b) (Vector set! 0 (rest (Vector ref 0 box)) box))
            (Vector set! 1 (if (null? b) #f (= b 27)) box)
            b)))))

(def %ap-waiting? (fn (_ reader ms) (reader (lit wait) ms)))

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

; The terminal the loop shows ST on: asked (lit draw), the screen drawn
; and sent; (lit resize), kept the terminal's size; (lit collect), the
; heap collected; (lit repaint), all drawn again at the next.
(def %ap-term
  (fn (_ st screen)
    (fn (_ what)
      (match ((eq? what (lit draw)) (%ap-show! st screen))
             ((eq? what (lit resize)) (%ap-resize! st screen))
             ((eq? what (lit collect)) (%ap-collect! st))
             (#t (Screen repaint screen))))))

; Keys taken one after another, already waiting, before the screen is
; drawn for them all; keys drawn before the heap is collected while more
; keep coming.
(def %ap-batch 8)
(def %ap-collect-keys 16)

; ST edited, its keys from READER, shown through TERM (%ap-term), until
; it quits or the keys end.  ROUNDS the quiet rounds since the last
; collect, DIRTY the keys since it, KEYS the keys since the last drawing.
; A key with another already waiting is not drawn: a held arrow draws
; once for the keys that came while the last screen was drawn, and the
; screen keeps up with the keyboard.  The collect after keys waits for a
; quiet round, so it never stands between a key and its screen.
(def app-loop
  (fn (self st reader term rounds dirty keys)
    (match
      ((edit-quit? st) ())
      ((%ap-waiting? reader (if (%ap-playing? st) 20 250))
        ((fn (_ key)
           (match
             ((null? key) ())
             (#t (do (if (eq? key (lit clear)) (term (lit repaint)) (edit-key! st key))
                     (match
                       ((if (< keys %ap-batch) (%ap-waiting? reader 0) #f)
                         (self st reader term rounds (+ dirty 1) (+ keys 1)))
                       (#t (do (edit-tick! st)
                               (term (lit draw))
                               (if (< dirty %ap-collect-keys)
                                 (self st reader term rounds (+ dirty 1) 0)
                                 (do (term (lit collect)) (self st reader term 0 0 0))))))))))
         (keys-read reader)))
      (#t (do (edit-settle! st)
              ((fn (_ drew)
                 (when drew (term (lit draw)))
                 (term (lit resize))
                 (if (if drew #t (if (< 0 dirty) #t (not (< rounds %ap-collect-rounds))))
                   (do (term (lit collect)) (self st reader term 0 0 0))
                   (self st reader term (+ rounds 1) 0 0)))
               (edit-tick! st)))))))

; Edit DOC, read from PATH, on the terminal, heard through PLAYER (nil
; for none), with the settings CONFIG when given (tracker/config); MSG
; shown first.  Answers the exit status.
(def app-edit
  (fn (_ doc path player msg . config)
    (def size (Term window 0))
    (def st (if (null? config) (edit-make doc path player) (edit-make doc path player (first config))))
    (edit-message! st msg)
    (def screen (Screen make (rest size) (first size)))
    (def token (Term raw! 0))
    (Term emit 1 (Str8 append (%ap-esc "[?1049h") (%ap-esc "[?25l")))
    (def failed
      (guard (e e)
        (do (%ap-show! st screen)
            (compile-module! (lit x/tui/screen))
            (%ap-collect! st)
            (app-loop st (%ap-reader) (%ap-term st screen) 0 0 0)
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

(provide tracker/app app-edit app-play app-loop)
