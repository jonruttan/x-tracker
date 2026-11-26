; # x-tracker -- a music tracker on x-lang
;
; ## tracker/file.x -- a .xon file of songs, read and written back
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; A file is read into a document: its top-level forms and the text
; between them (blanks and comments), each kept as the text it was
; (tracker/node).  A (song ...) form is also read into a song
; (tracker/song) the editor can change.  Written back, every piece is its
; own text again but a song that was changed, which is written from the
; song; so a file of songs and other forms, x-roguelike's music.xon among
; them, keeps its comments and layout everywhere the editor did not touch.
;
; A document is a list of pieces: (gap TEXT), (form TEXT HEAD) or (song
; TEXT SONG CHANGED), HEAD the form's first atom as a string.

(module tracker/file)

(import x/codec/xon)
(import x/sys/file)
(import tracker/node node-read node-form? node-text node-head)
(import tracker/song song-from-node song-text song-name song-wave-forms song-set-wave-form)

; TEXT as a document.  Raises a label 'value for text that is not forms,
; or a song that is not one.
(def file-parse
  (fn (_ text)
    (List reverse
      (List fold
        (fn (_ acc n)
          (match ((not (node-form? n))
                   (if (if (null? acc) #f (eq? (first (first acc)) (lit gap)))
                     (pair (list (lit gap) (Str8 append (List ref 1 (first acc)) (node-text n))) (rest acc))
                     (pair (list (lit gap) (node-text n)) acc)))
                 ((str=? (node-head n) "song") (pair (list (lit song) (node-text n) (song-from-node n) #f) acc))
                 (#t (pair (list (lit form) (node-text n) (node-head n)) acc))))
        () (node-read text)))))

; The document as text: each piece as it was read, a changed song as
; the song.
(def file-text
  (fn (_ doc)
    (Str8 join ""
      (List map (fn (_ p) (if (if (eq? (first p) (lit song)) (List ref 3 p) #f) (song-text (List ref 2 p)) (List ref 1 p)))
        doc))))

; The songs of DOC, in order.
(def file-songs
  (fn (_ doc) (List map (fn (_ p) (List ref 2 p)) (List filter (fn (_ p) (eq? (first p) (lit song))) doc))))

; DOC with its Ith song SONG, marked changed.
(def file-song!
  (fn (_ doc i song)
    ((fn (self ps k)
       (match ((null? ps) ())
              ((not (eq? (first (first ps)) (lit song))) (pair (first ps) (self (rest ps) k)))
              ((= k i) (pair (list (lit song) (List ref 1 (first ps)) song #t) (rest ps)))
              (#t (pair (first ps) (self (rest ps) (+ k 1))))))
     doc 0)))

; DOC with SONG added at its end, after a blank line.
(def file-add-song
  (fn (_ doc song)
    (def tail (if (null? doc) "" (List ref 1 (List last doc))))
    (def gap (match ((null? doc) "") ((Str8 ends? "\n\n" tail) "") ((Str8 ends? "\n" tail) "\n") (#t "\n\n")))
    (List append doc
      (if (str=? gap "") () (list (list (lit gap) gap)))
      (list (list (lit song) "" song #t) (list (lit gap) "\n")))))

; DOC without its Ith song: in its place an empty gap marked changed,
; until the document is written.
(def file-drop-song
  (fn (_ doc i)
    ((fn (self ps k)
       (match ((null? ps) ())
              ((not (eq? (first (first ps)) (lit song))) (pair (first ps) (self (rest ps) k)))
              ((= k i) (pair (list (lit gap) "" () #t) (rest ps)))
              (#t (pair (first ps) (self (rest ps) (+ k 1))))))
     doc 0)))

; Whether piece P has been changed: a song changed, a form made, a song
; dropped.
(def %fl-changed?
  (fn (_ p) (if (< (List length p) 4) #f (eq? (List ref 3 p) #t))))

; Whether any song or form of DOC has been changed.
(def file-changed?
  (fn (_ doc) (List any? %fl-changed? doc)))

; DOC with every song and form as written.
(def file-written
  (fn (_ doc)
    (List map (fn (_ p) (match ((not (%fl-changed? p)) p)
                               ((eq? (first p) (lit song)) (list (lit song) (song-text (List ref 2 p)) (List ref 2 p) #f))
                               (#t (List take 3 p))))
      doc)))

(def %fl-write (prim-ref (lit io) (lit write-to-str)))

; FORM as the file writes it: a symbol bare, a string in quotes, a list
; in parentheses.
(def file-form-text
  (fn (self v)
    (match ((symbol? v) (symbol->str v))
           ((null? v) "()")
           ((pair? v) (Str8 append "(" (Str8 join " " (List map self v)) ")"))
           (#t (%fl-write v)))))

(def %fl-wave? (fn (_ p) (if (eq? (first p) (lit form)) (str=? (List ref 2 p) "wave") #f)))

; Each wave DOC makes, as (WHERE . FORM): a (wave NAME ...) form beside
; the songs, then each an instrument makes with a (wave NAME ...) prop of
; more than its name; WHERE as a message names it.
(def %fl-wave-defs
  (fn (_ doc)
    (List append
      (List map (fn (_ p) (pair "beside the songs" (first (Xon parse (List ref 1 p))))) (List filter %fl-wave? doc))
      (List flat-map
        (fn (_ s)
          (List map (fn (_ d) (pair (Str8 append "in instrument " (first d) " of song " (%fl-write (song-name s))) (rest d)))
            (song-wave-forms s)))
        (file-songs doc)))))

(def %fl-same-name? (fn (_ a b) (eq? (List ref 1 (rest a)) (List ref 1 (rest b)))))

; The (wave NAME ...) forms of DOC, each name once, the first that makes
; it; with DIR, the directory DOC was read from, each sample's file (wave
; NAME (sample FILE ...)) named from it when FILE is not a path from the
; root.
(def file-waves
  (fn (_ doc . dir)
    (def at (if (null? dir) () (first dir)))
    (List map (fn (_ d) (file-sample-at (rest d) at))
      (List fold (fn (_ acc d) (if (List any? (fn (_ k) (%fl-same-name? k d)) acc) acc (List append acc (list d))))
        () (%fl-wave-defs doc)))))

; A message naming the first two waves of DOC that make one name
; differently, and where each is; nil when there are none.
(def file-wave-clash
  (fn (_ doc)
    ((fn (self ds)
       (if (null? ds) ()
         ((fn (_ other)
            (if (null? other) (self (rest ds))
              (Str8 append "x-tracker: two waves named " (symbol->str (List ref 1 (rest other))) " differ: "
                (file-form-text (rest (first ds))) " " (first (first ds)) ", and " (file-form-text (rest other)) " " (first other))))
          (List find (fn (_ d) (if (%fl-same-name? d (first ds)) (not (equal? (rest d) (rest (first ds)))) #f)) (rest ds)))))
     (%fl-wave-defs doc))))

; Whether wave form W is a sample's, (wave NAME (sample FILE ...)).
(def file-sample?
  (fn (_ w) (if (pair? (rest (rest w))) (if (pair? (List ref 2 w)) (eq? (first (List ref 2 w)) (lit sample)) #f) #f)))

(def file-sample-at
  (fn (_ w dir)
    (if (if (null? dir) #t (not (file-sample? w))) w
      ((fn (_ s)
         (def path (List ref 1 s))
         (if (Str8 starts? "/" path) w
           (list (lit wave) (List ref 1 w) (pair (lit sample) (pair (Str8 append dir "/" path) (rest (rest s)))))))
       (List ref 2 w)))))

; The directory PATH is in: "." for a name with no /.
(def file-dir
  (fn (_ path)
    ((fn (self i) (match ((< i 0) ".") ((str=? (Str8 sub i 1 path) "/") (if (= i 0) "/" (Str8 sub 0 i path))) (#t (self (- i 1)))))
     (- (Str8 length path) 1))))

; The (wave NAME AMP ...) form of DOC named NAME, a string, or nil.
(def file-wave
  (fn (_ doc name) (List find (fn (_ w) (str=? (symbol->str (List ref 1 w)) name)) (file-waves doc))))

; DOC with the wave NAME made of AMPS, the harmonics' strengths, its
; points, or its (sample FILE ...): in place of its form when it has one,
; in each instrument that makes it when no form does; or else on a line
; after its last wave, or else before its first song.
(def file-set-wave
  (fn (_ doc name amps)
    (def piece (list (lit form) (Str8 append "(wave " name (Str8 join "" (List map (fn (_ a) (Str8 append " " (file-form-text a))) amps)) ")") "wave" #t))
    (def named? (fn (_ p) (if (%fl-wave? p) (str=? (symbol->str (List ref 1 (first (Xon parse (List ref 1 p))))) name) #f)))
    (def made? (fn (_ p) (if (eq? (first p) (lit song)) (List any? (fn (_ d) (str=? (symbol->str (List ref 1 (rest d))) name)) (song-wave-forms (List ref 2 p))) #f)))
    (def last-wave (List fold (fn (_ at i) (if (%fl-wave? (List ref i doc)) i at)) () (List range 0 (List length doc))))
    (def first-song (List find-index (fn (_ p) (eq? (first p) (lit song))) doc))
    (match
      ((List any? (fn (_ p) (if (named? p) #t (made? p))) doc)
        ((fn (_ w)
           (List map (fn (_ p) (match ((named? p) piece)
                                      ((made? p) (list (lit song) (List ref 1 p) (song-set-wave-form (List ref 2 p) name w) #t))
                                      (#t p)))
             doc))
         (first (Xon parse (List ref 1 piece)))))
      ((not (null? last-wave))
        (List append (List take (+ last-wave 1) doc) (list (list (lit gap) "\n") piece) (List drop (+ last-wave 1) doc)))
      ((not (null? first-song))
        (List append (List take first-song doc) (list piece (list (lit gap) "\n\n")) (List drop first-song doc)))
      (#t (List append doc (list piece (list (lit gap) "\n")))))))

; The document in the file at PATH, read whole as an editor does; an
; empty one when there is no file.
(def file-read
  (fn (_ path)
    (if (File exists? path) (file-parse (File read-all path)) ())))

; DOC written to PATH: answers the document with every song as written.
(def file-write!
  (fn (_ doc path)
    (File write-all path (file-text doc))
    (file-written doc)))

(provide tracker/file file-form-text file-parse file-text file-songs file-song! file-add-song file-drop-song file-changed? file-written
  file-waves file-wave-clash file-wave file-set-wave file-read file-write! file-sample? file-sample-at file-dir)
