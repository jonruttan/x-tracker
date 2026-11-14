; # x-tracker -- a music tracker on x-lang
;
; ## tracker/player.x -- a song heard: x/audio/tracker on SDL's audio
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; A player plays a song (tracker/song) through a tracker (x/audio/tracker)
; into a mixer, whose blocks are put on an audio stream a little ahead of
; the speaker each time the caller's loop comes round (player-pump!).  No
; thread of SDL's calls into x: a stream is fed only by the pump.
;
; A song plays from a place in its order, round to the place again: the
; tracker is given the order turned to start there.  A pattern plays
; alone, over and over.  A change to the song while it plays is heard
; from the next pattern: the tracker takes the changed song when the
; pattern playing ends, its order turned to start at the pattern that
; was to come next.  Each song handed to the tracker has a name of its
; own, so the place it reports can be read back into the song's order.
;
; A player is a vector: 0 the class played through (Sdl, or any with
; its audio messages), 1 the stream, 2 the mixer, 3 the tracker, 4 the
; mode, song or pattern, 5 ((NAME . TURN) ...) the names given to the
; songs handed over and where their order was turned to start, 6 the
; songs handed over so far, 7 the order's length, 8 the waves, 9 whether
; it is playing, 10 the tension, 11 the pace, and for a note heard as
; it is typed (player-preview!), 12 a stream, 13 a mixer of their own
; and 14 the tracker that starts it, stopped once it has; 15 the rows
; of the tail a song played once rings out over, and 16 where the tracker
; stood after each block rendered (%pl-mark!).

(module tracker/player)

(import x/type/vector)
(import x/audio/mixer)
(import x/audio/tracker)
(import x/core/doors int/ int%)
(import tracker/song song-form song-order song-set-pattern song-prop song-instruments)

(def %pl-rate 44100)
(def %pl-block 1024)
; How far the music is kept ahead of the speaker, in bytes of frames: a
; second.  The editor's loop is held up by a redraw (some 75 ms) and a
; collect (up to some 180 ms, measured over music.xon), so a third of a
; second left little over.  A change is heard from the next pattern
; anyway, and the place shown is read from the marks, not the queue.  A
; note typed is queued only two blocks ahead, so it is heard at once.
(def %pl-ahead (* 4 %pl-rate))
(def %pl-preview-ahead (* 8 %pl-block))
(def %pl-preview-pattern "x-tracker-preview")
(def %pl-tail-pattern "x-tracker-tail")

(def %pl-get (fn (_ p k) (Vector ref k p)))
(def %pl-put! (fn (_ p k x) (Vector set! k x p)))

; A player playing through FRONT, nothing yet; WAVES the (wave NAME AMP
; ...) forms its songs' instruments may name.  Raises what FRONT raises
; when there is no audio to open.
(def player-open
  (fn (_ front waves)
    (Mixer jit!)
    (List for-each (fn (_ w) (Mixer wave! (List ref 1 w) (rest (rest w)))) waves)
    (def p (Vector make 17 ()))
    (%pl-put! p 0 front)
    (%pl-put! p 1 (front audio-open %pl-rate 2))
    (%pl-put! p 6 0)
    (%pl-put! p 8 waves)
    (%pl-put! p 9 #f)
    (%pl-put! p 10 0)
    (%pl-put! p 11 100)
    (%pl-put! p 12 (front audio-open %pl-rate 2))
    (%pl-put! p 13 (Mixer make %pl-rate %pl-block))
    p))

(def player-playing? (fn (_ p) (%pl-get p 9)))
(def player-mode (fn (_ p) (%pl-get p 4)))

; ORDER turned to start at AT.
(def %pl-turn (fn (_ order at) (List append (List drop at order) (List take at order))))

; The first wave named by an instrument of song form F that the mixer
; does not have, or nil.
(def %pl-missing-wave
  (fn (_ f)
    (def named
      (List flat-map
        (fn (_ x)
          (if (if (pair? x) (eq? (first x) (lit instrument)) #f)
            (List map (fn (_ prop) (List ref 1 prop))
              (List filter (fn (_ prop) (if (pair? prop) (if (eq? (first prop) (lit wave)) (if (pair? (rest prop)) (symbol? (List ref 1 prop)) #f) #f) #f))
                (rest (rest x))))
            ()))
        (rest (rest f))))
    (List find (fn (_ w) (null? (guard (e ()) (Mixer wave w)))) named)))

; Song form F, when the mixer has every wave it names.  Raises a label
; 'value for one it does not have, before the tracker meets it mid-block.
(def %pl-waves-known
  (fn (_ f)
    ((fn (_ w)
       (unless (null? w)
         (Err raise (lit value)
           (Str8 append "x-tracker: no wave named " (symbol->str w) ": read the file its (wave ...) form is in with -w FILE") ())))
     (%pl-missing-wave f))
    f))

; The form for S, named afresh, with ORDER, and the turn recorded.
(def %pl-form
  (fn (_ p s order turn)
    (%pl-waves-known (song-form s ()))
    (%pl-put! p 6 (+ (%pl-get p 6) 1))
    (def name (Str8 append "x-tracker " (Str8 str (%pl-get p 6))))
    (%pl-put! p 5 (pair (pair name turn) (List take 8 (%pl-get p 5))))
    ((fn (_ f) (pair (first f) (pair name (rest (rest f))))) (song-form s order))))

; P quiet at once: the rows stopped and the stream cleared.
(def player-stop!
  (fn (_ p)
    (when (%pl-get p 9)
      (do (Tracker stop! (%pl-get p 3))
          ((%pl-get p 0) audio-clear! (%pl-get p 1))))
    (%pl-put! p 9 #f)
    p))

; Rows of S's that last two seconds: what is left ringing when a song
; played once ends.
(def %pl-tail-rows
  (fn (_ s)
    (def row-ms (int/ 60000 (* (song-prop s "bpm" 90) (song-prop s "rows" 4))))
    (+ 1 (int/ 2000 (if (< 0 row-ms) row-ms 1)))))

; S with a pattern of TAIL held rows put after its order, so a song played
; once rings out before the tracker comes round to its start again.
(def %pl-with-tail
  (fn (_ s tail)
    (def inst (song-instruments s))
    (if (null? inst) s
      (song-set-pattern s %pl-tail-pattern (list (pair (first inst) (List repeat tail ".")))))))

; Play S through P: its order from place AT when MODE is song, round to
; AT again; its pattern PATTERN over and over when MODE is pattern; its
; order once from the start, and ringing out, when MODE is once.
; Raises a label 'value for a song the tracker cannot read.
(def player-start!
  (fn (_ p s mode at pattern)
    (player-stop! p)
    (def once (eq? mode (lit once)))
    (def order (match ((eq? mode (lit song)) (%pl-turn (song-order s) at))
                      (once (List append (song-order s) (list %pl-tail-pattern)))
                      (#t (list pattern))))
    (%pl-put! p 4 mode)
    (%pl-put! p 7 (List length (song-order s)))
    (%pl-put! p 15 (if once (%pl-tail-rows s) ()))
    (def t (Tracker make (%pl-form p (if once (%pl-with-tail s (%pl-tail-rows s)) s) order (if (eq? mode (lit song)) at 0))))
    (def m (Mixer make %pl-rate %pl-block))
    (Tracker tension! t (%pl-get p 10))
    (Tracker pace! t (%pl-get p 11))
    (%pl-put! p 2 m)
    (%pl-put! p 3 t)
    (Tracker play! t m)
    (%pl-put! p 16 (list (list 0 0 0 (if (eq? mode (lit song)) at 0))))
    (%pl-put! p 9 #t)
    p))

; The turn of the song the tracker is playing: where its order starts.
(def %pl-turn-now
  (fn (_ p t) ((fn (_ e) (if (null? e) 0 (rest e))) (List find (fn (_ e) (str=? (first e) (Tracker name t))) (%pl-get p 5)))))

; Where the tracker stood after the block just rendered: (CLOCK AT ROW
; TURN) put first in the record of them, the last 96 kept, so the place
; heard can be read back at a frame still queued.
(def %pl-mark!
  (fn (_ p)
    (def t (%pl-get p 3))
    (def place (Tracker place t))
    (%pl-put! p 16 (pair (list (Mixer clock (%pl-get p 2)) (first place) (rest place) (%pl-turn-now p t))
                         (List take 95 (%pl-get p 16))))))

; Where the song is being heard: (AT . ROW), AT a place in the song's
; own order and ROW a row of the pattern there.  The frame at the speaker
; is the frames rendered less those queued; the tracker stood at the
; place last marked by then, and the row before its next one is sounding.
(def player-place
  (fn (_ p)
    (if (not (%pl-get p 9)) (pair 0 0)
      (do (def heard (- (Mixer clock (%pl-get p 2)) (int/ ((%pl-get p 0) audio-queued (%pl-get p 1)) 4)))
          (def marks (%pl-get p 16))
          (def mark ((fn (_ m) (if (null? m) (List last marks) m)) (List find (fn (_ m) (not (< heard (first m)))) marks)))
          (def at (List ref 1 mark))
          (def row (List ref 2 mark))
          (def n (%pl-get p 7))
          (match ((if (eq? (%pl-get p 4) (lit once)) (not (< at n)) #f) (pair (- n 1) 0))
                 (#t (pair (if (if (eq? (%pl-get p 4) (lit pattern)) #t (= n 0)) at (int% (+ (List ref 3 mark) at) n))
                           (if (< 0 row) (- row 1) 0))))))))

; Whether a song played once has rung out: every row of its tail
; started.  Its last frames may still be queued (player-queued).
(def player-over?
  (fn (_ p)
    (if (if (%pl-get p 9) (eq? (%pl-get p 4) (lit once)) #f)
      ((fn (_ place) (if (= (first place) (%pl-get p 7)) (not (< (rest place) (- (%pl-get p 15) 1))) #f))
       (Tracker place (%pl-get p 3)))
      #f)))

; Bytes of the song's frames queued and not yet heard.
(def player-queued (fn (_ p) ((%pl-get p 0) audio-queued (%pl-get p 1))))

; S as it now is, heard from the next pattern.  Raises a label 'value
; for a song the tracker cannot read; the old one plays on.
(def player-update!
  (fn (_ p s pattern)
    (match
      ((not (%pl-get p 9)) ())
      ((eq? (%pl-get p 4) (lit song))
        ; The pattern after the one the tracker is starting rows of, in
        ; the song's own order.
        ((fn (_ t n)
           (def next (if (= n 0) 0 (int% (+ (+ (%pl-turn-now p t) (first (Tracker place t))) 1) n)))
           (Tracker song! t (%pl-form p s (%pl-turn (song-order s) next) next))
           (%pl-put! p 7 n))
         (%pl-get p 3) (List length (song-order s))))
      ((eq? (%pl-get p 4) (lit pattern)) (Tracker song! (%pl-get p 3) (%pl-form p s (list pattern) 0)))
      (#t ()))
    p))

; NOTE played on instrument INST of S, as a cell of four rows would
; play it, over whatever is playing.  Raises a label 'value for a note
; or an instrument the tracker cannot read.
(def player-preview!
  (fn (_ p s inst note)
    (def t (Tracker make (%pl-waves-known (song-form (song-set-pattern s %pl-preview-pattern (list (list inst note "." "." ".")))
                                                     (list %pl-preview-pattern)))))
    (unless (null? (%pl-get p 14)) (Tracker stop! (%pl-get p 14)))
    (Tracker play! t (%pl-get p 13))
    (%pl-put! p 14 t)
    p))

; Blocks of mixer M rendered onto STREAM until it is AHEAD bytes ahead
; of the speaker; after the first, AFTER is called.  Answers how many.
(def %pl-feed!
  (fn (_ p stream m ahead after)
    ((fn (self n)
       (if (< ((%pl-get p 0) audio-queued stream) ahead)
         (do ((%pl-get p 0) audio-put! stream (Mixer block! m) (* 4 %pl-block))
             (after)
             (self (+ n 1)))
         n))
     0)))

; The streams kept ahead of the speaker: the song's while it plays, the
; note typed's while it sounds.  Answers how many blocks were rendered.
(def player-pump!
  (fn (_ p)
    (+ (if (%pl-get p 9) (%pl-feed! p (%pl-get p 1) (%pl-get p 2) %pl-ahead (fn (_) (%pl-mark! p))) 0)
       (if (if (null? (%pl-get p 14)) (= 0 (Mixer playing (%pl-get p 13))) #f) 0
         (%pl-feed! p (%pl-get p 12) (%pl-get p 13) %pl-preview-ahead
           (fn (_) (unless (null? (%pl-get p 14)) (do (Tracker stop! (%pl-get p 14)) (%pl-put! p 14 ())))))))))

(def player-tension!
  (fn (_ p pct)
    (%pl-put! p 10 pct)
    (when (%pl-get p 9) (Tracker tension! (%pl-get p 3) pct))
    p))

(def player-pace!
  (fn (_ p pct)
    (%pl-put! p 11 pct)
    (when (%pl-get p 9) (Tracker pace! (%pl-get p 3) pct))
    p))

(def player-close
  (fn (_ p)
    (player-stop! p)
    ((%pl-get p 0) audio-close (%pl-get p 1))
    ((%pl-get p 0) audio-close (%pl-get p 12))
    ()))

(provide tracker/player player-open player-playing? player-mode player-start! player-stop! player-update!
  player-preview! player-pump! player-place player-over? player-queued player-tension! player-pace! player-close)
