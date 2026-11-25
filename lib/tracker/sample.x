; # x-tracker -- a music tracker on x-lang
;
; ## tracker/sample.x -- a sample's sound, edited
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; A sample's sound is PCM as (Wav decode) answers it and (Mixer sample!)
; plays it: FRAMES signed 16-bit little-endian samples, one channel, in a
; string.  The edits of the samples page work on a copy of it, so the one
; before an edit is kept to undo to.
;
; The loops that touch every frame are kernels, each written once as an
; integer form over byte addresses (x/tool/word-form): run as pure x, or
; compiled once the compiled ones write what the pure ones write, as the
; mixer's and the WAV reader's are.
(module tracker/sample)

(import x/tool/compiled)
(import x/tool/word-form word-form-pure)
(import x/sys/file)
(import x/codec/struct)
(import x/core/doors int& int* int+ int- int/ int< int= int>> int<< int->ptr ptr->int ptr-ref ptr-set! str->ptr str-make mem-copy)
(import x/num/fixed fixed*/)

; --- the kernels, as forms ----------------------------------------------------
;
; A frame S at byte address P is read (- (+ LO (<< HI 8)) (<< (& HI 128) 9)).
; T is a scratch word or two.

; Frames I to N of P each made ((S + OFF) * G) >> 24, held within 16 bits,
; G stepping by DG.  Answers 0.
(def %gain-form
  (lit (fn (self p t i n off g dg)
    (if (< i n)
      (do (%mem-set-at! t 0 (*>> (+ (- (+ (%mem-byte-ref-at p (+ i i)) (<< (%mem-byte-ref-at p (+ (+ i i) 1)) 8))
                                       (<< (& (%mem-byte-ref-at p (+ (+ i i) 1)) 128) 9))
                                    off)
                                 g 24))
          (%mem-set-at! t 0 (match ((< 32767 (%mem-ref-at t 0)) 32767)
                                   ((< (%mem-ref-at t 0) -32768) -32768)
                                   (#t (%mem-ref-at t 0))))
          (%mem-byte-set-at! p (+ i i) (& (%mem-ref-at t 0) 255))
          (%mem-byte-set-at! p (+ (+ i i) 1) (& (>> (%mem-ref-at t 0) 8) 255))
          (self p t (+ i 1) n off (+ g dg) dg))
      0))))

; Frames I to J of P, J the last, put in the other order.  Answers 0.
(def %reverse-form
  (lit (fn (self p t i j)
    (if (< i j)
      (do (%mem-set-at! t 0 (%mem-byte-ref-at p (+ i i)))
          (%mem-set-at! t 1 (%mem-byte-ref-at p (+ (+ i i) 1)))
          (%mem-byte-set-at! p (+ i i) (%mem-byte-ref-at p (+ j j)))
          (%mem-byte-set-at! p (+ (+ i i) 1) (%mem-byte-ref-at p (+ (+ j j) 1)))
          (%mem-byte-set-at! p (+ j j) (%mem-ref-at t 0))
          (%mem-byte-set-at! p (+ (+ j j) 1) (%mem-ref-at t 1))
          (self p t (+ i 1) (- j 1)))
      0))))

; The sum of frames I to N of P, from ACC.
(def %sum-form
  (lit (fn (self p i n acc)
    (if (< i n)
      (self p (+ i 1) n
            (+ acc (- (+ (%mem-byte-ref-at p (+ i i)) (<< (%mem-byte-ref-at p (+ (+ i i) 1)) 8))
                      (<< (& (%mem-byte-ref-at p (+ (+ i i) 1)) 128) 9))))
      acc))))

; The largest of M and the size of each of frames I to N of P.
(def %peak-form
  (lit (fn (self p t i n m)
    (if (< i n)
      (do (%mem-set-at! t 0 (- (+ (%mem-byte-ref-at p (+ i i)) (<< (%mem-byte-ref-at p (+ (+ i i) 1)) 8))
                               (<< (& (%mem-byte-ref-at p (+ (+ i i) 1)) 128) 9)))
          (%mem-set-at! t 0 (if (< (%mem-ref-at t 0) 0) (- 0 (%mem-ref-at t 0)) (%mem-ref-at t 0)))
          (self p t (+ i 1) n (if (< m (%mem-ref-at t 0)) (%mem-ref-at t 0) m)))
      m))))

; Frames I to N of O read from P at frame K and FRAC 65536ths of the
; next, straight between the two when LERP is 1 or the nearest before when
; it is 0, K stepping by STEP and FRAC by DF, the next frame held at LAST.
; Answers 0.
(def %resample-form
  (lit (fn (self o p t i n k frac step df last lerp)
    (if (< i n)
      (do (%mem-set-at! t 0 (- (+ (%mem-byte-ref-at p (+ k k)) (<< (%mem-byte-ref-at p (+ (+ k k) 1)) 8))
                               (<< (& (%mem-byte-ref-at p (+ (+ k k) 1)) 128) 9)))
          (%mem-set-at! t 1 (if (< k last) (+ k 1) last))
          (%mem-set-at! t 1 (- (+ (%mem-byte-ref-at p (+ (%mem-ref-at t 1) (%mem-ref-at t 1)))
                                  (<< (%mem-byte-ref-at p (+ (+ (%mem-ref-at t 1) (%mem-ref-at t 1)) 1)) 8))
                               (<< (& (%mem-byte-ref-at p (+ (+ (%mem-ref-at t 1) (%mem-ref-at t 1)) 1)) 128) 9)))
          (%mem-set-at! t 0 (+ (%mem-ref-at t 0) (*>> (- (%mem-ref-at t 1) (%mem-ref-at t 0)) (* frac lerp) 16)))
          (%mem-byte-set-at! o (+ i i) (& (%mem-ref-at t 0) 255))
          (%mem-byte-set-at! o (+ (+ i i) 1) (& (>> (%mem-ref-at t 0) 8) 255))
          (if (< (+ frac df) 65536)
            (self o p t (+ i 1) n (+ k step) (+ frac df) step df last lerp)
            (self o p t (+ i 1) n (+ (+ k step) 1) (- (+ frac df) 65536) step df last lerp)))
      0))))

(def %forms (list %gain-form %reverse-form %sum-form %peak-form %resample-form))
(def %pure (List map word-form-pure %forms))

(def %k-gain (List ref 0 %pure))
(def %k-reverse (List ref 1 %pure))
(def %k-sum (List ref 2 %pure))
(def %k-peak (List ref 3 %pure))
(def %k-resample (List ref 4 %pure))

(def %install!
  (fn (_ ks)
    (set! %k-gain (List ref 0 ks))
    (set! %k-reverse (List ref 1 ks))
    (set! %k-sum (List ref 2 ks))
    (set! %k-peak (List ref 3 ks))
    (set! %k-resample (List ref 4 ks))))

; --- the compiled kernels, adopted only when they agree --------------------------

(def %addr (fn (_ s) (ptr->int (str->ptr s))))
(def %scratch (fn (_) (str-make 32)))

; N frames of noise from SEED, as PCM.
(def %trial-pcm
  (fn (_ n seed)
    (def s (str-make (int+ (int* n 2) 1)))
    ((fn (self i x)
       (when (int< i (int* n 2))
         (do (ptr-set! (str->ptr s) i (int& (int>> x 7) 255) 1)
             (self (int+ i 1) (int& (int+ (int* x 1103515245) seed) 2147483647)))))
     0 seed)
    s))

(def %bytes-of (fn (_ s n) (List map (fn (_ i) (int& (ptr-ref (str->ptr s) i 1) 255)) (List range 0 n))))

; What each kernel of KS writes and answers, run on the same frames.
(def %trial
  (fn (_ ks)
    (def a (%trial-pcm 48 77))
    (def b (%trial-pcm 48 91))
    (def o (%trial-pcm 64 5))
    (list ((List ref 0 ks) (%addr a) (%addr (%scratch)) 0 40 -300 (int<< 3 23) 20000)
          ((List ref 1 ks) (%addr b) (%addr (%scratch)) 3 44)
          ((List ref 2 ks) (%addr a) 0 48 0)
          ((List ref 3 ks) (%addr b) (%addr (%scratch)) 0 48 0)
          ((List ref 4 ks) (%addr o) (%addr a) (%addr (%scratch)) 0 64 0 0 0 49152 47 1)
          (%bytes-of a 96) (%bytes-of b 96) (%bytes-of o 128))))

(def %agrees? (fn (_ engine) (equal? (%trial %pure) (%trial engine))))

(def %entry ())

; The compiled kernels, built and adopted the first time a long sound is
; edited, where the toolchain has a backend and they agree.
(def %jit-try!
  (fn (_)
    (when (null? %entry)
      (set! %entry
        (Compiled make-on-demand (lit tracker-sample) %pure
          (fn (_)
            (import x/tool/word-form-jit)
            ((prim-ref (lit word-form) (lit jit-make)) %forms %agrees?))
          %install!)))
    ((fn (_ entry) (when (eq? (entry state) (lit interpreted)) (entry compile!))) %entry)))

(def %long (fn (_ frames) (when (int< 4095 frames) (guard (_ ()) (%jit-try!)))))

; --- the sound ------------------------------------------------------------------

; A copy of frames FROM up to TO of PCM.
(def sample-copy
  (fn (_ pcm from to)
    (def n (%max 0 (int- to from)))
    (def s (str-make (int+ (int* n 2) 1)))
    (when (int< 0 n) (mem-copy (str->ptr s) (int->ptr (int+ (%addr pcm) (int* from 2))) (int* n 2)))
    s))

(def %max (fn (_ a b) (if (int< a b) b a)))
(def %min (fn (_ a b) (if (int< a b) a b)))

; Frame I of PCM, -32768 to 32767.
(def sample-frame
  (fn (_ pcm i)
    (def lo (int& (ptr-ref (str->ptr pcm) (int* i 2) 1) 255))
    (def hi (int& (ptr-ref (str->ptr pcm) (int+ (int* i 2) 1) 1) 255))
    (int- (int+ lo (int<< hi 8)) (int<< (int& hi 128) 9))))

; FRAMES of PCM with frames FROM up to TO through the gain kernel, from
; G 2^24ths stepping by DG, OFF added first: a new PCM.
(def %gained
  (fn (_ pcm frames from to off g dg)
    (%long frames)
    (def s (sample-copy pcm 0 frames))
    (%k-gain (%addr s) (%addr (%scratch)) from to off g dg)
    s))

(def %one 16777216)

; The FRAMES of PCM, frames FROM up to TO at PCT percent, held within 16
; bits.
(def sample-amplify
  (fn (_ pcm frames from to pct) (%gained pcm frames from to 0 (fixed*/ pct %one 100) 0)))

; PCM upside down: each frame its negative.
(def sample-invert (fn (_ pcm frames) (%gained pcm frames 0 frames 0 (int- 0 %one) 0)))

; PCM with frames FROM up to TO silent.
(def sample-silence (fn (_ pcm frames from to) (%gained pcm frames from to 0 0 0)))

; PCM rising from silence over frames FROM up to TO, when IN is #t, or
; falling to it.
(def sample-fade
  (fn (_ pcm frames from to in)
    (def n (%max 1 (int- to from)))
    (if in (%gained pcm frames from to 0 0 (int/ %one n))
      (%gained pcm frames from to 0 %one (int- 0 (int/ %one n))))))

; The mean of the FRAMES of PCM, summed a block of 32768 at a time so no
; sum passes 2^30.
(def sample-mean
  (fn (_ pcm frames)
    (%long frames)
    ((fn (self at mean)
       (if (int< at frames)
         ((fn (_ n)
            (self (int+ at n)
                  (int+ mean (fixed*/ (int- (int/ (%k-sum (%addr pcm) at (int+ at n) 0) n) mean) n (int+ at n)))))
          (%min 32768 (int- frames at)))
         mean))
     0 0)))

; PCM about 0: its mean taken from every frame.
(def sample-centre
  (fn (_ pcm frames) (%gained pcm frames 0 frames (int- 0 (sample-mean pcm frames)) %one 0)))

; The largest size of a frame of PCM's FRAMES.
(def sample-peak
  (fn (_ pcm frames) (%long frames) (%k-peak (%addr pcm) (%addr (%scratch)) 0 frames 0)))

; PCM as loud as it can be without clipping: its largest frame 32767.
(def sample-normalise
  (fn (_ pcm frames)
    (def m (sample-peak pcm frames))
    (if (int= m 0) (sample-copy pcm 0 frames)
      (%gained pcm frames 0 frames 0 (fixed*/ 32767 %one m) 0))))

; PCM backwards.
(def sample-reverse
  (fn (_ pcm frames)
    (%long frames)
    (def s (sample-copy pcm 0 frames))
    (%k-reverse (%addr s) (%addr (%scratch)) 0 (int- frames 1))
    s))

; The FRAMES of PCM without frames FROM up to TO: (PCM FRAMES).
(def sample-cut
  (fn (_ pcm frames from to)
    (def n (int- frames (int- to from)))
    (def s (str-make (int+ (int* n 2) 1)))
    (when (int< 0 from) (mem-copy (str->ptr s) (str->ptr pcm) (int* from 2)))
    (when (int< to frames)
      (mem-copy (int->ptr (int+ (%addr s) (int* from 2))) (int->ptr (int+ (%addr pcm) (int* to 2))) (int* (int- frames to) 2)))
    (list s n)))

; The FRAMES of PCM drawn out or squeezed to N, read straight between its
; frames when LERP is #t, or else each the frame before it: (PCM N).
(def sample-resample
  (fn (_ pcm frames n lerp)
    (%long n)
    (def o (str-make (int+ (int* n 2) 1)))
    ; A step of FRAMES / N frames, whole and in 65536ths.
    (def step (int/ frames n))
    (def df (fixed*/ (int- frames (int* step n)) 65536 n))
    (%k-resample (%addr o) (%addr pcm) (%addr (%scratch)) 0 n 0 0 step df (int- frames 1) (if lerp 1 0))
    (list o n)))

; The least and most frame of each of COLS runs of PCM's FRAMES, as
; (LEAST . MOST), each from up to 32 frames spread over its run.
(def sample-peaks
  (fn (_ pcm frames cols)
    (List map
      (fn (_ c)
        (def from (fixed*/ c frames cols))
        (def to (%max (int+ from 1) (fixed*/ (int+ c 1) frames cols)))
        (def step (%max 1 (int/ (int- to from) 32)))
        ((fn (self i lo hi)
           (if (int< i to)
             ((fn (_ s) (self (int+ i step) (%min lo s) (%max hi s))) (sample-frame pcm i))
             (pair lo hi)))
         from 32767 -32768))
      (List range 0 cols))))

; --- WAV ------------------------------------------------------------------------

(def %wav-spec
  (lit ((riff str 4) (size u32) (wave str 4) (fmt str 4) (fmt-size u32) (format u16) (chans u16) (rate u32)
        (byte-rate u32) (align u16) (bits u16) (data str 4) (data-size u32))))

; A WAV file's header: CHANS channels of 16 bits at RATE frames a second,
; BYTES of frames.
(def sample-wav-header
  (fn (_ chans rate bytes)
    (bytes->str
      (Struct pack %wav-spec
        (list (pair (lit riff) "RIFF") (pair (lit size) (+ 36 bytes)) (pair (lit wave) "WAVE") (pair (lit fmt) "fmt ")
              (pair (lit fmt-size) 16) (pair (lit format) 1) (pair (lit chans) chans) (pair (lit rate) rate)
              (pair (lit byte-rate) (* (* 2 chans) rate)) (pair (lit align) (* 2 chans)) (pair (lit bits) 16)
              (pair (lit data) "data") (pair (lit data-size) bytes))))))

; The FRAMES of PCM, RATE frames a second, written to PATH as a mono WAV
; file.  Raises a label 'value for a file that cannot be written.
(def sample-write!
  (fn (_ pcm frames rate path)
    (def fd (File open path (list (lit wronly) (lit creat) (lit trunc))))
    (when (< fd 0) (Err raise (lit value) (Str8 append "x-tracker: cannot write " path) ()))
    (File write fd (sample-wav-header 1 rate (* 2 frames)) 44)
    (File write fd pcm (* 2 frames))
    (File close fd)
    frames))


; --- the settings -------------------------------------------------------------
;
; A sample is (sample FILE [ROOT] [START END] SETTING ...), ARGS all but
; its head: FILE the WAV file, ROOT the note it sounds at its rate, START
; and END its loop, and each SETTING a list as Impulse Tracker keeps it:
;
;   (volume 0..64)         its default volume, 64 as recorded
;   (global 0..64)         its global volume, 64 as recorded
;   (pan 0..64)            where it is heard, 32 the middle; none, where
;                          the instrument puts it
;   (speed HZ)             the frames a second that sound C4, IT's C-5
;   (sustain START END)    its sustain loop
;   (vibrato SPEED DEPTH RATE WAVE)  its vibrato, WAVE sine, ramp,
;                          square or random

; The setting KEY of ARGS, without its head, or nil.
(def sample-setting
  (fn (_ args key)
    ((fn (_ s) (if (null? s) () (rest s)))
     (List find (fn (_ a) (if (pair? a) (eq? (first a) key) #f)) (rest args)))))

; ARGS with the setting KEY made VALS, or taken out when VALS is nil.
(def sample-set-setting
  (fn (_ args key vals)
    (def kept (List filter (fn (_ a) (not (if (pair? a) (eq? (first a) key) #f))) (rest args)))
    (pair (first args) (if (null? vals) kept (List append kept (list (pair key vals)))))))

; The loop of ARGS, (START END), or nil.
(def sample-loop
  (fn (_ args) ((fn (_ ns) (if (= (List length ns) 2) ns ())) (List filter number? (rest args)))))

; ARGS with the loop LOOP, (START END), or none when LOOP is nil.
(def sample-set-loop
  (fn (_ args loop)
    (def root (List filter str? (rest args)))
    (def settings (List filter pair? (rest args)))
    (pair (first args) (List append root (if (null? loop) () loop) settings))))

; The root note of ARGS, a string, or nil.
(def sample-root (fn (_ args) (List find str? (rest args))))

(provide tracker/sample sample-copy sample-frame sample-amplify sample-invert sample-silence sample-fade sample-mean
  sample-centre sample-peak sample-normalise sample-reverse sample-cut sample-resample sample-peaks
  sample-wav-header sample-write! sample-setting sample-set-setting sample-loop sample-set-loop sample-root)
