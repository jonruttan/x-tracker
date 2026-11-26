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
; A song or a pattern can start at a row: the tracker is first given a
; song whose one pattern is the rest of the pattern from that row, and
; the song as it would be played from that pattern's end is waiting for
; it.  A pattern can be looped over a range of its rows, a pattern of
; those rows played over and over.  The row such a pattern reports is
; moved by the row it was cut from (its offset), so the place read back
; is a row of the pattern in the song.
;
; A channel or an instrument muted, or another soloed, is played as held
; rows: the song handed to the tracker has "." in each of its cells.  A
; change of who is heard starts the playing again from the row after the
; one heard, so it is heard at once.  A song rendered to a WAV file is
; played once through the same mixer and tracker, its blocks written to
; the file instead of a stream.
;
; A player is a vector: 0 the class played through (Sdl, or any with
; its audio messages; nil for a player that only renders), 1 the stream,
; 2 the mixer, 3 the tracker, 4 the mode, song, pattern or once, 5
; ((NAME TURN OFFSET) ...) the names given to the songs handed over,
; where their order was turned to start and the row their first pattern
; was cut from, 6 the songs handed over so far, 7 the order's length, 8
; the waves, 9 whether it is playing, 10 the tension, 11 the pace, and
; for a note heard as it is typed (player-preview!), 12 a stream, 13 a
; mixer of their own and 14 the trackers that start them, stopped once they
; have; 15 the rows of the tail a song played once rings out over, 16
; where the tracker stood after each block rendered (%pl-mark!), 17 the
; rows of each place in the order played (the song's own order, or the
; one pattern), 18 the channels muted, 19 the instruments muted, 20 the
; channels soloed, 21 the instruments soloed, 22 the volume, 23 the rows
; looped, (FROM . TO), or nil, 24 the song playing, 25 its pattern
; played alone, 26 the places of the order looped, (FROM . TO), or nil,
; and 27 the first of the places a song playing plays.

(module tracker/player)

(import x/type/vector)
(import x/sys/file)
(import x/sys/gc)
(import x/codec/struct)
(import x/audio/mixer)
(import x/audio/tracker)
(import x/codec/wav)
(import tracker/file file-sample?)
(import tracker/sample sample-setting sample-loop sample-root)
(import x/core/doors int/ int%)
(import tracker/song song-note-name song-form song-order song-set-pattern song-prop song-instruments song-pattern song-patterns
  pattern-rows)

(def %pl-rate 44100)
(def %pl-block 1024)
; How far the music is kept ahead of the speaker, in bytes of frames: a
; second.  The editor's loop is held up by a note typed (some 90 ms), a
; redraw (some 105 ms) and a collect (40 to 180 ms), measured over the
; demo and music.xon, so a third of a second left little over.  A change
; is heard from the next pattern anyway, and the place shown is read
; from the marks, not the queue.  A note typed is kept as far ahead: its
; stream is cleared when the next is typed, so it is still heard at once.
(def %pl-ahead (* 4 %pl-rate))
(def %pl-preview-pattern "x-tracker-preview")
(def %pl-tail-pattern "x-tracker-tail")
(def %pl-from-pattern "x-tracker-from")
(def %pl-loop-pattern "x-tracker-loop")
; The most a render writes: an hour.  A song played once ends, but a
; pace of 10 percent makes a long one ten times longer.
(def %pl-render-most (* 3600 %pl-rate))

(def %pl-get (fn (_ p k) (Vector ref k p)))
(def %pl-put! (fn (_ p k x) (Vector set! k x p)))

; The (wave NAME ...) form W made in the mixer: drawn through its points
; when it has them, (wave NAME (POSITION LEVEL) ...); a recorded sound,
; (wave NAME (sample FILE [ROOT] [START END])), read from the WAV file
; FILE, sounding at ROOT, else at the note the file says, else C4, and
; looping from START to END, else the file's loop, else not at all;
; else of its harmonics, (wave NAME AMP ...).
(def player-give!
  (fn (_ w)
    (match
      ((file-sample? w) (%pl-sample! (List ref 1 w) (rest (List ref 2 w))))
      ((pair? (List ref 2 w)) (Mixer shape! (List ref 1 w) (rest (rest w))))
      (#t (Mixer wave! (List ref 1 w) (rest (rest w)))))))

; Sounds edited and not yet written, by name: ((NAME RATE FRAMES PCM
; LOOP ROOT) ...), each as (Wav decode) answers a file's.
(def %pl-edited (Vector make 1 ()))

; The sound of the sample NAME, a symbol, as edited, or nil when it is
; its file's.
(def player-pcm
  (fn (_ name) ((fn (_ e) (if (null? e) () (rest e))) (Assoc entry name (Vector ref 0 %pl-edited)))))

; The sample NAME heard as D, (RATE FRAMES PCM LOOP ROOT), in place of
; its file, ARGS its (sample FILE ...) without the head; or as its file
; again when D is nil.
(def player-pcm!
  (fn (_ name args d)
    (Vector set! 0 (List append (List filter (fn (_ e) (not (eq? (first e) name))) (Vector ref 0 %pl-edited))
                               (if (null? d) () (list (pair name d))))
      %pl-edited)
    (%pl-sample! name args)))

; The names of the samples edited and not yet written.
(def player-edited (fn (_) (List map first (Vector ref 0 %pl-edited))))

; The WAV file at PATH, as (Wav decode) answers it.
(def player-wav
  (fn (_ path) (Wav decode (File read-all path) 0 (Assoc get (lit size) (File stat path)))))

; The sample NAME given to the mixer from ARGS, (FILE [ROOT] [START END]
; SETTING ...): its sound as edited, or else its file's.  (speed HZ)
; sounds C4 at HZ, before ROOT and the file's root; a loop not within
; the sound is left out.
(def %pl-sample!
  (fn (_ name args)
    (def kept (player-pcm name))
    (def d (if (null? kept) (player-wav (first args)) kept))
    (def frames (List ref 1 d))
    (def speed (sample-setting args (lit speed)))
    (def root (sample-root args))
    (def given (if (null? (sample-loop args)) (List ref 3 d) (sample-loop args)))
    (def loop (if (if (pair? given) (if (< -1 (first given)) (if (< (first given) (List ref 1 given)) (not (< frames (List ref 1 given))) #f) #f) #f)
                given ()))
    (def note (match ((not (null? speed)) "C4")
                     ((not (null? root)) root)
                     ((not (null? (List ref 4 d))) (song-note-name (- (List ref 4 d) 12)))
                     (#t "C4")))
    (def rate (if (null? speed) (first d) (first speed)))
    (if (null? loop)
      (Mixer sample! name (List ref 2 d) frames rate note)
      (Mixer sample! name (List ref 2 d) frames rate note (first loop) (List ref 1 loop)))))

; Song form F with each instrument that plays a sample of WAVES heard as
; the sample's settings say: its gain times the sample's volume and
; global volume, each of 64, and at the sample's pan when it has one.
(def player-sampled
  (fn (_ f waves)
    (pair (first f) (pair (List ref 1 f)
      (List map (fn (_ x) (if (if (pair? x) (eq? (first x) (lit instrument)) #f) (%pl-inst-sampled x waves) x)) (rest (rest f)))))))

(def %pl-inst-sampled
  (fn (_ x waves)
    (def props (rest (rest x)))
    (def named (List find (fn (_ prop) (if (pair? prop) (if (eq? (first prop) (lit wave)) (pair? (rest prop)) #f) #f)) props))
    (def w (if (null? named) () (List find (fn (_ w) (if (file-sample? w) (eq? (List ref 1 w) (List ref 1 named)) #f)) waves)))
    (if (null? w) x
      ((fn (_ args)
         (def one (fn (_ key) ((fn (_ v) (if (null? v) 64 (first v))) (sample-setting args key))))
         (def scale (* (one (lit volume)) (one (lit global))))
         (def pan (sample-setting args (lit pan)))
         (def had (List find (fn (_ prop) (if (pair? prop) (eq? (first prop) (lit gain)) #f)) props))
         (def gain (if (null? had) 100 (List ref 1 had)))
         (def drop (if (null? pan) (list (lit gain)) (list (lit gain) (lit pan))))
         (if (if (= scale 4096) (null? pan) #f) x
           (pair (first x) (pair (List ref 1 x)
             (List append (List filter (fn (_ prop) (not (if (pair? prop) (List includes? (first prop) drop) #f))) props)
               (list (list (lit gain) (int/ (* gain scale) 4096)))
               (if (null? pan) () (list (list (lit pan) (int/ (* (- (first pan) 32) 100) 32)))))))))
       (rest (List ref 2 w))))))

; A player playing through FRONT, nothing yet; WAVES the (wave ...)
; forms its songs' instruments may name.  Raises what FRONT raises
; when there is no audio to open.  With FRONT nil, a player that only
; renders (player-render!): it opens no audio.
(def player-open
  (fn (_ front waves)
    (Mixer jit!)
    (List for-each player-give! waves)
    (def p (Vector make 28 ()))
    (%pl-put! p 0 front)
    (unless (null? front) (%pl-put! p 1 (front audio-open %pl-rate 2)))
    (%pl-put! p 6 0)
    (%pl-put! p 8 waves)
    (%pl-put! p 9 #f)
    (%pl-put! p 10 0)
    (%pl-put! p 11 100)
    (unless (null? front) (%pl-put! p 12 (front audio-open %pl-rate 2)))
    (%pl-put! p 13 (Mixer make %pl-rate %pl-block))
    (%pl-put! p 22 100)
    p))

; The (wave ...) forms the mixer was given.
(def player-waves (fn (_ p) (%pl-get p 8)))

; The (wave ...) forms WAVES given to the mixer, each in place
; of a wave of its name; one the mixer already has as it is, is not
; made again.  A song playing hears them from its next pattern.
(def player-waves!
  (fn (_ p waves)
    (def had (%pl-get p 8))
    (def fresh (List filter (fn (_ w) (not (List any? (fn (_ h) (equal? h w)) had))) waves))
    (List for-each player-give! fresh)
    (%pl-put! p 8
      (List append (List filter (fn (_ h) (not (List any? (fn (_ w) (eq? (List ref 1 w) (List ref 1 h))) fresh))) had) fresh))
    p))

; Whether the mixer has a wave named NAME, a string: one it was given or
; one of its own (sine, noise).
(def player-wave?
  (fn (_ name) (not (null? (guard (e ()) (Mixer wave (str->sym name)))))))

(def player-playing? (fn (_ p) (%pl-get p 9)))
(def player-mode (fn (_ p) (%pl-get p 4)))

; The pattern a pattern played alone is, or nil.
(def player-pattern (fn (_ p) (if (eq? (%pl-get p 4) (lit pattern)) (%pl-get p 25) ())))

; How many voices are sounding or waiting to start, 0 when nothing plays.
(def player-voices (fn (_ p) (if (%pl-get p 9) (Mixer playing (%pl-get p 2)) 0)))

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
           ((fn (_ n) (Str8 append "x-tracker: no wave named " n ": make it with :wave " n " AMP ..., or a (wave " n " AMP ...) form beside the songs; -w SONGS.xon borrows the waves of another song file")) (symbol->str w)) ())))
     (%pl-missing-wave f))
    f))

; --- who is heard ------------------------------------------------------------

; Whether channel I, of instrument INST, is heard: neither it nor its
; instrument muted, and when anything is soloed, it or its instrument.
(def player-hears?
  (fn (_ p i inst)
    (def solo-ch (%pl-get p 20))
    (def solo-in (%pl-get p 21))
    (if (if (List includes? i (%pl-get p 18)) #t (List includes? inst (%pl-get p 19))) #f
      (if (if (null? solo-ch) (null? solo-in) #f) #t
        (if (List includes? i solo-ch) #t (List includes? inst solo-in))))))

; Whether anything is muted or soloed.
(def %pl-hushing?
  (fn (_ p) (not (List all? (fn (_ l) (null? l)) (list (%pl-get p 18) (%pl-get p 19) (%pl-get p 20) (%pl-get p 21))))))

; S with every channel not heard held: "." in each of its cells.
(def %pl-hushed
  (fn (_ p s)
    (if (not (%pl-hushing? p)) s
      (List fold
        (fn (_ s2 pat)
          (song-set-pattern s2 (first pat)
            (List map (fn (_ i)
                        (def ch (List ref i (rest pat)))
                        (if (player-hears? p i (first ch)) ch (pair (first ch) (List repeat (List length (rest ch)) "."))))
              (List range 0 (List length (rest pat))))))
        s (song-patterns s)))))

; The form for S, named afresh, with ORDER, and the turn and the offset
; of its first pattern recorded.
(def %pl-form
  (fn (_ p s order turn offset)
    (%pl-waves-known (song-form s ()))
    (%pl-put! p 6 (+ (%pl-get p 6) 1))
    (def name (Str8 append "x-tracker " (Str8 str (%pl-get p 6))))
    (%pl-put! p 5 (pair (list name turn offset) (List take 8 (%pl-get p 5))))
    ((fn (_ f) (pair (first f) (pair name (rest (rest f))))) (player-sampled (song-form (%pl-hushed p s) order) (%pl-get p 8)))))

; S with a pattern NAME of rows FROM up to TO of its pattern PAT: a
; channel shorter held to TO.
(def %pl-slice
  (fn (_ s name pat from to)
    (song-set-pattern s name
      (List map (fn (_ ch) (pair (first ch) (List take (- to from) (List append (List drop from (rest ch)) (List repeat (- to from) ".")))))
        (song-pattern s pat)))))

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

; The rows of each pattern of ORDER, a pattern of S each, kept for
; player-place.
(def %pl-rows!
  (fn (_ p s order)
    (%pl-put! p 17 (List map (fn (_ name) (pattern-rows (song-pattern s name))) order))))

(def %pl-clamp (fn (_ x least most) (if (< x least) least (if (< most x) most x))))

; Pattern PAT of S as it plays alone, its rows looped when P has a range:
; (S2 BASE OFFSET END), BASE the pattern played in S2, its first row
; OFFSET and the row after its last END, rows of PAT.
(def %pl-base
  (fn (_ p s pat)
    (def rows (pattern-rows (song-pattern s pat)))
    (def range (%pl-get p 23))
    (if (null? range) (list s pat 0 rows)
      ((fn (_ from to) (list (%pl-slice s %pl-loop-pattern pat from (+ to 1)) %pl-loop-pattern from (+ to 1)))
       (%pl-clamp (first range) 0 (- rows 1)) (%pl-clamp (rest range) (%pl-clamp (first range) 0 (- rows 1)) (- rows 1))))))

; Play S through P: its order from place AT when MODE is song, round to
; AT again; its pattern PATTERN over and over when MODE is pattern, or
; the rows of it P loops (player-loop!); its order once from the start,
; and ringing out, when MODE is once.  Raises a label 'value for a song
; the tracker cannot read.
(def player-start!
  (fn (_ p s mode at pattern) (player-start-at! p s mode at pattern 0)))

; As player-start!, from ROW of the pattern at AT (song) or of PATTERN
; (pattern); a song played once starts at its start.
(def player-start-at!
  (fn (_ p s mode at pattern row)
    (player-stop! p)
    (%pl-put! p 24 s)
    (%pl-put! p 25 pattern)
    (%pl-put! p 4 mode)
    (%pl-put! p 7 (List length (song-order s)))
    (%pl-put! p 15 ())
    ; (FIRST PENDING TURN OFFSET): the form the tracker starts on, the
    ; one waiting for its pattern's end or nil, and the first's turn and
    ; offset.
    (def plan
      (match
        ((eq? mode (lit once))
          (do (%pl-put! p 15 (%pl-tail-rows s))
              (%pl-rows! p s (song-order s))
              (list (%pl-form p (%pl-with-tail s (%pl-tail-rows s)) (List append (song-order s) (list %pl-tail-pattern)) 0 0) () 0 0)))
        ((eq? mode (lit song))
          (do (def span (%pl-span p (song-order s)))
              (def order (List take (+ 1 (- (rest span) (first span))) (List drop (first span) (song-order s))))
              (def n (List length order))
              (def inside (if (< at (first span)) #f (not (< (rest span) at))))
              (%pl-put! p 7 n)
              (%pl-put! p 27 (first span))
              (%pl-rows! p s order)
              ; AT and ROW within the places played; the loop's first
              ; for a place outside it.
              ((fn (_ at row)
                 (def name (if (< at n) (List ref at order) ()))
                 (if (if (null? name) #t (not (if (< 0 row) (< row (pattern-rows (song-pattern s name))) #f)))
                   (list (%pl-form p s (%pl-turn order at) at 0) () at 0)
                   (list (%pl-form p (%pl-slice s %pl-from-pattern name row (pattern-rows (song-pattern s name))) (list %pl-from-pattern) at row)
                         (%pl-form p s (%pl-turn order (int% (+ at 1) n)) (int% (+ at 1) n) 0)
                         at row)))
               (if inside (- at (first span)) 0) (if inside row 0))))
        (#t
          ((fn (_ b)
             (def s2 (first b))
             (def base (List ref 1 b))
             (def off (List ref 2 b))
             (def end (List ref 3 b))
             (%pl-put! p 17 (list end))
             (if (if (< off row) (< row end) #f)
               (list (%pl-form p (%pl-slice s2 %pl-from-pattern pattern row end) (list %pl-from-pattern) 0 row)
                     (%pl-form p s2 (list base) 0 off) 0 row)
               (list (%pl-form p s2 (list base) 0 off) () 0 off)))
           (%pl-base p s pattern)))))
    (def t (Tracker make (first plan)))
    (unless (null? (List ref 1 plan)) (Tracker song! t (List ref 1 plan)))
    (def m (Mixer make %pl-rate %pl-block))
    (Mixer gain! m (%pl-get p 22))
    (Tracker tension! t (%pl-get p 10))
    (Tracker pace! t (%pl-get p 11))
    (%pl-put! p 2 m)
    (%pl-put! p 3 t)
    (Tracker play! t m)
    (%pl-put! p 16 (list (list 0 0 0 (List ref 2 plan) (List ref 3 plan))))
    (%pl-put! p 9 #t)
    p))

; The record of the song the tracker is playing: (NAME TURN OFFSET).
(def %pl-entry-now
  (fn (_ p t)
    ((fn (_ e) (if (null? e) (list "" 0 0) e)) (List find (fn (_ e) (str=? (first e) (Tracker name t))) (%pl-get p 5)))))

; Where the tracker stood after the block just rendered: (CLOCK AT ROW
; TURN OFFSET) put first in the record of them, the last 96 kept, so the
; place heard can be read back at a frame still queued.
(def %pl-mark!
  (fn (_ p)
    (def t (%pl-get p 3))
    (def place (Tracker place t))
    (def e (%pl-entry-now p t))
    (%pl-put! p 16 (pair (list (Mixer clock (%pl-get p 2)) (first place) (rest place) (List ref 1 e) (List ref 2 e))
                         (List take 95 (%pl-get p 16))))))

; Where the song is being heard: (AT . ROW), AT a place in the order
; played (the loop's) and ROW a row of the pattern there.  The frame at
; the speaker is the frames rendered less those queued; the tracker stood
; at the place last marked by then, and the row before its next one is
; sounding: when the next is a pattern's first, the last row of the
; pattern before it in the order.  A row of a pattern cut from another
; is moved by the row it was cut from.
(def %pl-place
  (fn (_ p)
    (if (not (%pl-get p 9)) (pair 0 0)
      (do (def heard (- (Mixer clock (%pl-get p 2)) (int/ ((%pl-get p 0) audio-queued (%pl-get p 1)) 4)))
          (def marks (%pl-get p 16))
          (def mark ((fn (_ m) (if (null? m) (List last marks) m)) (List find (fn (_ m) (not (< heard (first m)))) marks)))
          (def at (List ref 1 mark))
          (def row (List ref 2 mark))
          (def off (List ref 4 mark))
          (def n (%pl-get p 7))
          (def mode (%pl-get p 4))
          (def rows (%pl-get p 17))
          ; The place in the order played: the song's own, the one pattern.
          (def place (if (if (eq? mode (lit pattern)) #t (= n 0)) at (int% (+ (List ref 3 mark) at) n)))
          (def size (if (eq? mode (lit pattern)) 1 n))
          (match ((if (eq? mode (lit once)) (not (< at n)) #f) (pair (- n 1) 0))
                 ((< 0 row) (pair place (+ off (- row 1))))
                 ; Nothing sounded yet, or a song played once at its start.
                 ((if (= 0 (first mark)) #t (if (eq? mode (lit once)) (= at 0) #f)) (pair place off))
                 ((null? rows) (pair place off))
                 (#t ((fn (_ before) (pair before (- (List ref (if (eq? mode (lit pattern)) 0 before) rows) 1)))
                      (if (eq? mode (lit pattern)) at (int% (+ (- place 1) size) size)))))))))

; Where the playing is heard, (AT . ROW), AT a place in the song's order.
(def player-place
  (fn (_ p)
    ((fn (_ place)
       (if (if (%pl-get p 9) (eq? (%pl-get p 4) (lit song)) #f)
         (pair (+ (first place) (%pl-get p 27)) (rest place))
         place))
     (%pl-place p))))

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
           (def next (if (= n 0) 0 (int% (+ (+ (List ref 1 (%pl-entry-now p t)) (first (Tracker place t))) 1) n)))
           (Tracker song! t (%pl-form p s (%pl-turn (song-order s) next) next 0))
           (%pl-put! p 7 n)
           (%pl-put! p 24 s)
           (%pl-rows! p s (song-order s)))
         (%pl-get p 3) (List length (song-order s))))
      ((eq? (%pl-get p 4) (lit pattern))
        ((fn (_ b)
           (Tracker song! (%pl-get p 3) (%pl-form p (first b) (list (List ref 1 b)) 0 (List ref 2 b)))
           (%pl-put! p 24 s)
           (%pl-put! p 25 pattern)
           (%pl-put! p 17 (list (List ref 3 b))))
         (%pl-base p s pattern)))
      (#t ()))
    p))

; The playing started again from the row after the one heard, so a
; change of who is heard is heard at once.  A song played once is left
; as it is.
(def %pl-again!
  (fn (_ p)
    (when (%pl-get p 9)
      (do (def s (%pl-get p 24))
          (def pattern (%pl-get p 25))
          (def heard (player-place p))
          (match
            ((eq? (%pl-get p 4) (lit song))
              ((fn (_ order)
                 (def at (first heard))
                 (def rows (pattern-rows (song-pattern s (List ref at order))))
                 (if (< (+ (rest heard) 1) rows)
                   (player-start-at! p s (lit song) at pattern (+ (rest heard) 1))
                   (player-start-at! p s (lit song) (%pl-next p order at) pattern 0)))
               (song-order s)))
            ((eq? (%pl-get p 4) (lit pattern)) (player-start-at! p s (lit pattern) 0 pattern (+ (rest heard) 1)))
            (#t (player-update! p s pattern)))))
    p))

; X added to XS, or taken out when it is there.
(def %pl-toggle
  (fn (_ x xs) (if (List includes? x xs) (List filter (fn (_ y) (not (equal? y x))) xs) (pair x xs))))

(def %pl-slot (fn (_ kind solo) (+ (if solo 20 18) (if (eq? kind (lit channel)) 0 1))))

; Channel X (a number) when KIND is channel, or instrument X (a name)
; when it is instrument, muted, or heard again when it was.  Heard from
; the row after the one heard.
(def player-mute!
  (fn (_ p kind x)
    (%pl-put! p (%pl-slot kind #f) (%pl-toggle x (%pl-get p (%pl-slot kind #f))))
    (%pl-again! p)))

; As player-mute!, soloed: while anything is, only what is soloed is heard.
(def player-solo!
  (fn (_ p kind x)
    (%pl-put! p (%pl-slot kind #t) (%pl-toggle x (%pl-get p (%pl-slot kind #t))))
    (%pl-again! p)))

(def player-muted? (fn (_ p kind x) (List includes? x (%pl-get p (%pl-slot kind #f)))))
(def player-soloed? (fn (_ p kind x) (List includes? x (%pl-get p (%pl-slot kind #t)))))

; Every channel and instrument heard again.
(def player-unmute!
  (fn (_ p)
    (def was (%pl-hushing? p))
    (List for-each (fn (_ i) (%pl-put! p i ())) (list 18 19 20 21))
    (when was (%pl-again! p))
    p))

; The rows a pattern played alone loops: (FROM . TO), or nil for all of
; them.  Heard when the pattern is next started.
(def player-loop! (fn (_ p range) (%pl-put! p 23 range) p))
(def player-loop (fn (_ p) (%pl-get p 23)))

; The places of the order a song plays over and over: (FROM . TO), or
; nil for all of them.  Heard when the song is next started.
(def player-order-loop! (fn (_ p range) (%pl-put! p 26 range) p))
(def player-order-loop (fn (_ p) (%pl-get p 26)))

; The places of ORDER P plays in a song: (FROM . TO), the order loop
; held within ORDER, or all of it.
(def %pl-span
  (fn (_ p order)
    (def n (List length order))
    (def range (%pl-get p 26))
    (if (if (null? range) #t (= n 0)) (pair 0 (- n 1))
      ((fn (_ from) (pair from (%pl-clamp (rest range) from (- n 1)))) (%pl-clamp (first range) 0 (- n 1))))))

; The place after AT in ORDER as P plays it: round to the loop's first
; after its last.
(def %pl-next
  (fn (_ p order at)
    (def span (%pl-span p order))
    (if (< at (rest span)) (+ at 1) (first span))))

(def player-tension (fn (_ p) (%pl-get p 10)))
(def player-pace (fn (_ p) (%pl-get p 11)))
(def player-volume (fn (_ p) (%pl-get p 22)))

; The volume everything is heard at, PCT percent of full, at once.
(def player-volume!
  (fn (_ p pct)
    (%pl-put! p 22 pct)
    (when (%pl-get p 9) (Mixer gain! (%pl-get p 2) pct))
    (Mixer gain! (%pl-get p 13) pct)
    p))

; --- rendering ----------------------------------------------------------------

; A WAV file's header: 16-bit stereo at the mixer's rate, BYTES of frames.
(def %pl-wav-spec
  (lit ((riff str 4) (size u32) (wave str 4) (fmt str 4) (fmt-size u32) (format u16) (chans u16) (rate u32)
        (byte-rate u32) (align u16) (bits u16) (data str 4) (data-size u32))))

(def %pl-wav-header
  (fn (_ bytes)
    (bytes->str
      (Struct pack %pl-wav-spec
        (list (pair (lit riff) "RIFF") (pair (lit size) (+ 36 bytes)) (pair (lit wave) "WAVE") (pair (lit fmt) "fmt ")
              (pair (lit fmt-size) 16) (pair (lit format) 1) (pair (lit chans) 2) (pair (lit rate) %pl-rate)
              (pair (lit byte-rate) (* 4 %pl-rate)) (pair (lit align) 4) (pair (lit bits) 16) (pair (lit data) "data")
              (pair (lit data-size) bytes))))))

; S played once through, ringing out, written to PATH as a WAV file, at
; P's tension, pace and volume and with only what P hears.  Answers the
; frames written.  Raises a label 'value for a song the tracker cannot
; read or a file that cannot be written.
(def player-render!
  (fn (_ p s path)
    (def tail (%pl-tail-rows s))
    (def n (List length (song-order s)))
    (def t (Tracker make (%pl-form p (%pl-with-tail s tail) (List append (song-order s) (list %pl-tail-pattern)) 0 0)))
    (def m (Mixer make %pl-rate %pl-block))
    (Mixer gain! m (%pl-get p 22))
    (Tracker tension! t (%pl-get p 10))
    (Tracker pace! t (%pl-get p 11))
    (Tracker play! t m)
    (def fd (File open path (list (lit wronly) (lit creat) (lit trunc))))
    (when (< fd 0) (Err raise (lit value) (Str8 append "x-tracker: cannot write " path) ()))
    (File write fd (%pl-wav-header 0) 44)
    ; Blocks until the tail's last row has started, or the tracker has
    ; left the tail (a row shorter than a block), or an hour.
    (def frames
      ((fn (self frames k tailing)
         (def place (Tracker place t))
         (def in-tail (= (first place) n))
         (if (if (if in-tail (not (< (rest place) (- tail 1))) #f) #t
               (if (if tailing (not in-tail) #f) #t (not (< frames %pl-render-most))))
           frames
           (do (File write fd (Mixer block! m) (* 4 %pl-block))
               (when (= 0 (int% k 64)) (Heap collect))
               (self (+ frames %pl-block) (+ k 1) (if tailing #t in-tail)))))
       0 1 #f))
    (File seek fd 0)
    (File write fd (%pl-wav-header (* 4 frames)) 44)
    (File close fd)
    (Tracker stop! t)
    frames))


; Song form F with only what a note on instrument INST needs: its props
; and effects, that instrument, and the preview pattern; the tracker reads
; every pattern of a form it is given.
(def %pl-preview-form
  (fn (_ f inst)
    (pair (first f)
      (pair (List ref 1 f)
        (List filter
          (fn (_ x)
            (match ((not (pair? x)) #t)
                   ((eq? (first x) (lit instrument)) (str=? (symbol->str (List ref 1 x)) inst))
                   ((eq? (first x) (lit pattern)) (str=? (symbol->str (List ref 1 x)) %pl-preview-pattern))
                   (#t #t)))
          (rest (rest f)))))))

; NOTE played on instrument INST of S, as a cell of four rows would
; play it, over whatever is playing.  The note typed before is cut off
; where it was heard: its stream is cleared, so this one is heard at
; once.  With CHORD, as a MIDI keyboard's notes are, a note typed before
; and not yet started is started too, so the notes of a chord all sound.
; Raises a label 'value for a note or an instrument the tracker cannot
; read.
(def player-preview!
  (fn (_ p s inst note . chord)
    (def t (Tracker make (player-sampled (%pl-waves-known
                           (%pl-preview-form
                             (song-form (song-set-pattern s %pl-preview-pattern (list (list inst note "." "." ".")))
                                        (list %pl-preview-pattern))
                             inst)) (%pl-get p 8))))
    (unless (if (pair? chord) (first chord) #f) (%pl-stop-previews! p))
    ((%pl-get p 0) audio-clear! (%pl-get p 12))
    (Tracker play! t (%pl-get p 13))
    (%pl-put! p 14 (pair t (%pl-get p 14)))
    p))

; The trackers of the notes heard stopped: each has started its note.
(def %pl-stop-previews!
  (fn (_ p)
    (List for-each (fn (_ t) (Tracker stop! t)) (%pl-get p 14))
    (%pl-put! p 14 ())))

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
         (%pl-feed! p (%pl-get p 12) (%pl-get p 13) %pl-ahead
           (fn (_) (%pl-stop-previews! p)))))))

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
    (unless (null? (%pl-get p 0))
      (do ((%pl-get p 0) audio-close (%pl-get p 1))
          ((%pl-get p 0) audio-close (%pl-get p 12))))
    ()))

(provide tracker/player player-open player-playing? player-mode player-start! player-start-at! player-stop! player-update!
  player-give! player-preview! player-pump! player-place player-over? player-queued player-tension! player-pace! player-close
  player-waves player-waves! player-wave? player-tension player-pace player-volume player-volume! player-hears?
  player-mute! player-solo! player-muted? player-soloed? player-unmute! player-loop! player-loop player-render!
  player-pcm player-pcm! player-edited player-wav player-sampled player-pattern player-voices player-order-loop! player-order-loop)
