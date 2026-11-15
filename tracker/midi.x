; # x-tracker -- a music tracker on x-lang
;
; ## tracker/midi.x -- a Standard MIDI File read into a song
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; A MIDI file of format 0 or 1 is read into a song (tracker/song): its
; tracks' events merged in time, each note placed on the row nearest
; where it is heard.  The rows are of real time, not of the file's
; beats: the song's bpm is the file's first tempo and its rows a beat
; ROWS, and each event's time in microseconds, through every change of
; tempo, is taken to the nearest row, so a file that slows or speeds is
; heard as it was written in a song of one tempo.
;
; Each MIDI channel and program is an instrument named for its General
; MIDI family (piano, organ, strings, ...), and channel 10's notes are
; drums, an instrument a kind (kick, snare, hat, ...).  An instrument
; plays as many channels as its notes need at once, a note in the first
; channel free; a note's velocity is its gain, NOTE:PCT, and a channel's
; first volume and pan are its instrument's (gain) and (pan).  A note
; held under the sustain pedal ends when the pedal is let go.
;
; The song is cut into patterns of four bars of the file's first meter
; (tracker/score).

(module tracker/midi)

(import x/type/vector)
(import x/core/doors int/ int% str-byte-ref char->int)
(import tracker/song song-note-name)
(import tracker/score score-song)

(def %md-fail (fn (_ what) (Err raise (lit value) (Str8 append "x-tracker: " what) ())))
(def %md-max (fn (_ a b) (if (< a b) b a)))
(def %md-min (fn (_ a b) (if (< a b) a b)))

; --- the bytes -------------------------------------------------------------

(def %md-byte (fn (_ buf i) (char->int (str-byte-ref buf i))))
(def %md-u16 (fn (_ buf i) (+ (* 256 (%md-byte buf i)) (%md-byte buf (+ i 1)))))
(def %md-u32 (fn (_ buf i) (+ (* 65536 (%md-u16 buf i)) (%md-u16 buf (+ i 2)))))

; Whether the four bytes of BUF at I are TAG's.
(def %md-tag?
  (fn (_ buf i tag) (List all? (fn (_ k) (= (%md-byte buf (+ i k)) (char->int (str-byte-ref tag k)))) (List range 0 4))))

; The variable-length number at I, below END: (N . NEXT).
(def %md-vlq
  (fn (_ buf i end)
    ((fn (self i n)
       (when (not (< i end)) (%md-fail "a MIDI file ends inside a number"))
       ((fn (_ b) (if (< b 128) (pair (+ (* n 128) b) (+ i 1)) (self (+ i 1) (+ (* n 128) (- b 128)))))
        (%md-byte buf i)))
     i 0)))

(def %md-pow2 (fn (_ d) (List fold (fn (_ n _) (* n 2)) 1 (List range 0 d))))

; --- the events ------------------------------------------------------------
;
; An event is (TICK RANK KIND ARG ...): on CH KEY VEL, off CH KEY, program
; CH N, control CH N V, tempo US (a beat's microseconds), meter NUM DEN.
; RANK orders the events of one tick: the notes let go first, the notes
; started last.

; The events of the track whose bytes run from I to END, in order.
(def %md-track
  (fn (_ buf i end)
    ((fn (self i tick status acc)
       (if (not (< i end)) (List reverse acc)
         (do (def d (%md-vlq buf i end))
             (def t (+ tick (first d)))
             (def j (rest d))
             (when (not (< j end)) (%md-fail "a MIDI track ends inside an event"))
             (def b (%md-byte buf j))
             (match
               ((= b 255)
                 (do (def ty (%md-byte buf (+ j 1)))
                     (def ln (%md-vlq buf (+ j 2) end))
                     (def at (rest ln))
                     (def n (first ln))
                     (when (< end (+ at n)) (%md-fail "a MIDI track ends inside an event"))
                     (def ev (match ((if (= ty 81) (= n 3) #f)
                                      (list t 1 (lit tempo) (+ (* 65536 (%md-byte buf at)) (%md-u16 buf (+ at 1)))))
                                    ((if (= ty 88) (< 1 n) #f)
                                      (list t 1 (lit meter) (%md-byte buf at) (%md-pow2 (%md-byte buf (+ at 1)))))
                                    (#t ())))
                     (def acc2 (if (null? ev) acc (pair ev acc)))
                     (if (= ty 47) (List reverse acc2) (self (+ at n) t status acc2))))
               ((if (= b 240) #t (= b 247))
                 ((fn (_ ln) (self (+ (rest ln) (first ln)) t status acc)) (%md-vlq buf (+ j 1) end)))
               ((< 240 b) (self (+ j 1) t status acc))
               (#t
                 (do (def run (< b 128))
                     (def st (if run status b))
                     (when (null? st) (%md-fail "a MIDI event has no status"))
                     (def k (if run j (+ j 1)))
                     (def hi (int/ st 16))
                     (def ch (int% st 16))
                     (def size (if (if (= hi 12) #t (= hi 13)) 1 2))
                     (when (< end (+ k size)) (%md-fail "a MIDI track ends inside an event"))
                     (def a (%md-byte buf k))
                     (def v (if (= size 2) (%md-byte buf (+ k 1)) 0))
                     (def ev (match ((if (= hi 9) (< 0 v) #f) (list t 2 (lit on) ch a v))
                                    ((if (= hi 8) #t (= hi 9)) (list t 0 (lit off) ch a))
                                    ((= hi 12) (list t 1 (lit program) ch a))
                                    ((= hi 11) (list t 1 (lit control) ch a v))
                                    (#t ())))
                     (self (+ k size) t st (if (null? ev) acc (pair ev acc)))))))))
     i 0 () ())))

; The file in REGION, (BUF START LEN), as (DIVISION SMPTE EVENTS): the
; ticks a beat (or, SMPTE true, a second), and every track's events
; merged in time.  Raises a label 'value for bytes that are no MIDI file
; of format 0 or 1.
(def %md-read
  (fn (_ region)
    (def buf (first region))
    (def start (List ref 1 region))
    (def end (+ start (List ref 2 region)))
    (unless (if (< (+ start 13) end) (%md-tag? buf start "MThd") #f) (%md-fail "not a MIDI file"))
    (def format (%md-u16 buf (+ start 8)))
    (when (< 1 format) (%md-fail (Str8 append "a MIDI file of format " (Str8 str format) " is not imported; 0 and 1 are")))
    (def division (%md-u16 buf (+ start 12)))
    (def smpte (< 32767 division))
    (def tracks
      ((fn (self i acc)
         (if (< end (+ i 8)) (List reverse acc)
           ((fn (_ n) (self (+ (+ i 8) n) (if (%md-tag? buf i "MTrk") (pair (%md-track buf (+ i 8) (%md-min end (+ (+ i 8) n))) acc) acc)))
            (%md-u32 buf (+ i 4)))))
       (+ (+ start 8) (%md-u32 buf (+ start 4))) ()))
    (list (if smpte (* (- 256 (int/ division 256)) (int% division 256)) division) smpte
      (List sort (fn (_ a b) (if (< (first a) (first b)) #t (if (= (first a) (first b)) (< (List ref 1 a) (List ref 1 b)) #f)))
        (List flat-map (fn (_ ev) ev) tracks)))))

; --- the notes -------------------------------------------------------------
;
; A note is (CH PROGRAM KEY START END VEL), START and END rows.  ROW-US is
; a row's microseconds; a beat lasts the tempo's microseconds, a tick
; DIVISION of it, or with SMPTE a second DIVISION ticks.  Answers (NOTES
; VOLUMES PANS), each channel's first volume and pan or nil.

(def %md-notes
  (fn (_ events division smpte row-us)
    (def held (Vector make 2048 ()))
    (def program (Vector make 16 0))
    (def pedal (Vector make 16 #f))
    (def pending (Vector make 16 ()))
    (def volume (Vector make 16 ()))
    (def pan (Vector make 16 ()))
    (def out (Vector make 1 ()))
    (def clock (Vector make 3 0))
    (Vector set! 2 (if smpte 1000000 500000) clock)
    (def us-at (fn (_ tick) (+ (Vector ref 1 clock) (int/ (* (- tick (Vector ref 0 clock)) (Vector ref 2 clock)) division))))
    (def row-at (fn (_ tick) (int/ (+ (us-at tick) (int/ row-us 2)) row-us)))
    (def add! (fn (_ ch s row) (Vector set! 0 (pair (list ch (List ref 2 s) (first s) (List ref 1 s) row (List ref 3 s)) (Vector ref 0 out)) out)))
    (def flush! (fn (_ ch row) (List for-each (fn (_ s) (add! ch s row)) (Vector ref ch pending)) (Vector set! ch () pending)))
    (List for-each
      (fn (_ e)
        (def kind (List ref 2 e))
        (def row (row-at (first e)))
        (match
          ((eq? kind (lit on))
            ((fn (_ ch k) (Vector set! (+ (* ch 128) k) (List append (Vector ref (+ (* ch 128) k) held) (list (list k row (Vector ref ch program) (List ref 5 e)))) held))
             (List ref 3 e) (List ref 4 e)))
          ((eq? kind (lit off))
            ((fn (_ ch at)
               (def starts (Vector ref at held))
               (unless (null? starts)
                 (do (Vector set! at (rest starts) held)
                     (if (Vector ref ch pedal) (Vector set! ch (pair (first starts) (Vector ref ch pending)) pending)
                       (add! ch (first starts) row)))))
             (List ref 3 e) (+ (* (List ref 3 e) 128) (List ref 4 e))))
          ((eq? kind (lit program)) (Vector set! (List ref 3 e) (List ref 4 e) program))
          ((eq? kind (lit control))
            ((fn (_ ch n v)
               (match ((= n 64) (if (< 63 v) (Vector set! ch #t pedal) (do (Vector set! ch #f pedal) (flush! ch row))))
                      ((= n 7) (when (null? (Vector ref ch volume)) (Vector set! ch v volume)))
                      ((= n 10) (when (null? (Vector ref ch pan)) (Vector set! ch v pan)))
                      (#t ())))
             (List ref 3 e) (List ref 4 e) (List ref 5 e)))
          ((if (eq? kind (lit tempo)) (not smpte) #f)
            ((fn (_ us) (Vector set! 0 (first e) clock) (Vector set! 1 us clock) (Vector set! 2 (List ref 3 e) clock))
             (us-at (first e))))
          (#t ())))
      events)
    (def last (if (null? events) 0 (row-at (first (List last events)))))
    (List for-each (fn (_ ch) (flush! ch last)) (List range 0 16))
    (List for-each (fn (_ at) (List for-each (fn (_ s) (add! (int/ at 128) s last)) (Vector ref at held))) (List range 0 2048))
    (list (List reverse (Vector ref 0 out)) (Vector ->list volume) (Vector ->list pan))))

; --- the instruments -------------------------------------------------------

; General MIDI's sixteen families of eight programs: (NAME GAIN PROPS).
(def %md-families
  (list (list "piano" 40 "(wave triangle) (cut 80) (env (0 0) (3 80) (300 50) (3000 0)) (release 300)")
        (list "bells" 35 "(wave sine) (env (0 0) (2 80) (1500 0)) (release 600)")
        (list "organ" 30 "(wave square) (cut 30) (env (0 0) (10 60)) (release 80)")
        (list "guitar" 40 "(wave saw) (cut 35) (env (0 0) (3 80) (250 40) (2500 0)) (release 150)")
        (list "bass" 50 "(wave triangle) (cut 45) (env (0 0) (5 90) (400 60)) (release 100)")
        (list "strings" 35 "(wave saw) (cut 28) (env (0 0) (90 60) (600 55)) (release 300)")
        (list "ensemble" 30 "(wave saw) (cut 25) (env (0 0) (150 55)) (release 400) (voice (detune -6)) (voice (detune 6))")
        (list "brass" 35 "(wave saw) (cut 45) (env (0 0) (30 70) (300 55)) (release 120)")
        (list "reed" 35 "(wave pulse) (width (0 30)) (cut 40) (env (0 0) (25 65) (300 55)) (release 100)")
        (list "pipe" 40 "(wave sine) (env (0 0) (40 65) (300 55)) (release 120)")
        (list "lead" 30 "(wave square) (cut 55) (env (0 0) (5 70) (300 55)) (release 100)")
        (list "pad" 30 "(wave triangle) (cut 30) (env (0 0) (500 55)) (release 800)")
        (list "fx" 30 "(wave pulse) (width (0 20) (2000 50)) (cut 40) (env (0 0) (200 50)) (release 500)")
        (list "ethnic" 40 "(wave saw) (cut 40) (env (0 0) (2 85) (600 0)) (release 150)")
        (list "percussive" 45 "(wave sine) (env (0 0) (1 90) (400 0)) (release 100)")
        (list "effects" 25 "(wave noise) (hz 1) (cut 40) (env (0 0) (50 50) (800 0)) (release 300)")))

; Channel 10's kinds of drum: (NAME KEYS FIXED GAIN PROPS), FIXED whether
; it has a pitch of its own; the last takes every key the others do not.
(def %md-drums
  (list (list "kick" (list 35 36) #t 70 "(wave sine) (note \"C2\") (env (0 0) (2 95) (140 0)) (bend (0 700) (45 0)) (release 30)")
        (list "snare" (list 37 38 39 40) #t 45 "(env (0 0) (1 60) (30 25) (160 0)) (release 40) (voice (wave noise) (hz 1) (cut 55)) (voice (wave sine) (note \"G3\") (gain 50))")
        (list "hat" (list 42 44) #t 25 "(wave noise) (hz 1) (cut 85) (env (0 0) (1 30) (35 0)) (release 15)")
        (list "open-hat" (list 46) #t 22 "(wave noise) (hz 1) (cut 80) (env (0 0) (1 30) (220 0)) (release 40)")
        (list "tom" (list 41 43 45 47 48 50) #f 55 "(wave sine) (env (0 0) (2 90) (300 0)) (bend (0 300) (60 0)) (release 40)")
        (list "cymbal" (list 49 51 52 53 55 57 59) #t 20 "(wave noise) (hz 1) (cut 95) (env (0 0) (2 30) (900 0)) (release 200)")
        (list "percussion" () #f 25 "(wave metal) (env (0 0) (1 50) (120 0)) (release 30)")))

(def %md-drum-kind
  (fn (_ key) ((fn (_ d) (if (null? d) (List last %md-drums) d)) (List find (fn (_ d) (List includes? key (List ref 1 d))) %md-drums))))

; A note's group: (CH . PROGRAM), or on channel 10 (9 . KIND).
(def %md-group
  (fn (_ n) (if (= (first n) 9) (pair 9 (first (%md-drum-kind (List ref 2 n)))) (pair (first n) (List ref 1 n)))))

(def %md-group=? (fn (_ a b) (if (= (first a) (first b)) (if (= (first a) 9) (str=? (rest a) (rest b)) (= (rest a) (rest b))) #f)))

; A note's cell: its name and, below full velocity, its gain.
(def %md-cell
  (fn (_ key vel fixed)
    (def semi (if fixed 48 (- key 12)))
    (Str8 append (song-note-name (if (< semi 0) (+ semi (* 12 (int/ (- 11 semi) 12))) semi))
      ((fn (_ pct) (if (< 99 pct) "" (Str8 append ":" (Str8 str (%md-max 1 pct))))) (int/ (+ (* vel 100) 63) 127)))))

; --- the song --------------------------------------------------------------

; The song a MIDI file makes: REGION (BUF START LEN) its bytes, NAME the
; song's name, ROWS its rows a beat.  Raises a label 'value for bytes that
; are no MIDI file of format 0 or 1, or one with no notes.
(def midi-song
  (fn (_ region name rows)
    (def file (%md-read region))
    (def division (first file))
    (def smpte (List ref 1 file))
    (def events (List ref 2 file))
    (when (= division 0) (%md-fail "a MIDI file of no ticks a beat"))
    (def tempo ((fn (_ e) (if (if (null? e) #t smpte) 500000 (List ref 3 e)))
                (List find (fn (_ e) (if (= (first e) 0) (eq? (List ref 2 e) (lit tempo)) #f)) events)))
    (def bpm (%md-min 999 (%md-max 1 (int/ (+ 60000000 (int/ tempo 2)) tempo))))
    (def row-ms (int/ 60000 (* bpm rows)))
    (when (< row-ms 1) (%md-fail "too many rows a beat for the tempo"))
    (def meter ((fn (_ e) (if (null? e) (list 4 4) (List drop 3 e))) (List find (fn (_ e) (eq? (List ref 2 e) (lit meter))) events)))
    (def prows (* 4 (%md-max 1 (int/ (* (* rows 4) (first meter)) (List ref 1 meter)))))
    (def got (%md-notes events division smpte (* row-ms 1000)))
    (def notes (first got))
    (when (null? notes) (%md-fail "the MIDI file has no notes"))
    ; The groups, the channels in order and drums last, each with its notes
    ; by start, the higher of a chord first.
    (def groups
      (List sort (fn (_ a b) (match ((not (= (first (first a)) (first b))) ((fn (_ x y) (< x y)) (if (= (first (first a)) 9) 16 (first (first a))) (if (= (first (first b)) 9) 16 (first (first b)))))
                                    ((= (first (first a)) 9) #f)
                                    (#t (< (rest (first a)) (rest (first b))))))
        (List fold (fn (_ gs n)
                     (def g (%md-group n))
                     (if (List any? (fn (_ e) (%md-group=? (first e) g)) gs)
                       (List map (fn (_ e) (if (%md-group=? (first e) g) (pair (first e) (pair n (rest e))) e)) gs)
                       (List append gs (list (list g n)))))
          () notes)))
    (def groups2
      (List map (fn (_ e) (pair (first e) (List sort (fn (_ a b) (if (< (List ref 3 a) (List ref 3 b)) #t (if (= (List ref 3 a) (List ref 3 b)) (< (List ref 2 b) (List ref 2 a)) #f)))
                                             (List reverse (rest e)))))
        groups))
    ; Each group's instrument: (NAME DRUM FIXED TEXT).
    (def insts
      (List fold
        (fn (_ acc e)
          (def g (first e))
          (def drum (= (first g) 9))
          (def kind (if drum (List find (fn (_ d) (str=? (first d) (rest g))) %md-drums) (List ref (int/ (rest g) 8) %md-families)))
          (def base (first kind))
          (def taken (fn (_ nm) (List any? (fn (_ i) (str=? (first i) nm)) acc)))
          (def nm ((fn (self k) ((fn (_ c) (if (taken c) (self (+ k 1)) c)) (if (= k 1) base (Str8 append base "-" (Str8 str k))))) 1))
          (def vol ((fn (_ v) (if (null? v) 100 v)) (List ref (first g) (List ref 1 got))))
          (def pn (List ref (first g) (List ref 2 got)))
          (def gain (%md-max 1 (int/ (* (List ref (if drum 3 1) kind) vol) 127)))
          (List append acc
            (list (list nm drum (if drum (List ref 2 kind) #f)
                    (Str8 append "(instrument " nm " " (List ref (if drum 4 2) kind) " (gain " (Str8 str gain) ")"
                      (if (if (null? pn) #t (= pn 64)) "" (Str8 append " (pan " (Str8 str (if (< pn 64) (int/ (* (- pn 64) 100) 64) (int/ (* (- pn 64) 100) 63))) ")"))
                      ")")))))
        () groups2))
    ; The channels, (INSTRUMENT DRUM CELLS) each, CELLS a vector of rows.
    (def total (+ 1 (List fold (fn (_ m n) (%md-max m (List ref 4 n))) 0 notes)))
    (def columns
      (List flat-map
        (fn (_ k)
          (def inst (List ref k insts))
          (def drum (List ref 1 inst))
          (def cols (Vector make 1 ()))
          (List for-each
            (fn (_ n)
              (def end (if drum (+ (List ref 3 n) 1) (List ref 4 n)))
              (def cs (Vector ref 0 cols))
              (def free (List find-index (fn (_ c) (not (< (List ref 3 n) (first c)))) cs))
              (def col (if (null? free)
                         ((fn (_ c) (Vector set! 0 (List append cs (list c)) cols) c) (pair 0 (Vector make total ".")))
                         (List ref free cs)))
              (def v (rest col))
              (Vector set! (List ref 3 n) (%md-cell (List ref 2 n) (List ref 5 n) (List ref 2 inst)) v)
              (when (if drum #f (< end total)) (Vector set! end "-" v))
              (Vector set! 0 (List map (fn (_ c) (if (same? c col) (pair end (rest c)) c)) (Vector ref 0 cols)) cols))
            (rest (List ref k groups2)))
          (List map (fn (_ c) (list (first inst) (not drum) (rest c))) (Vector ref 0 cols)))
        (List range 0 (List length insts))))
    (score-song name (Str8 append "(bpm " (Str8 str bpm) ") (rows " (Str8 str rows) ") (ticks 6)\n  (limit 90 120)")
      (List map (fn (_ i) (List ref 3 i)) insts) columns prows)))

(provide tracker/midi midi-song)
