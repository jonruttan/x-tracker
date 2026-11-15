; # x-tracker -- a music tracker on x-lang
;
; ## tracker/import.x -- another program's music read into a song
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; A file is known by its first bytes, not its name: "MThd" is a Standard
; MIDI File (tracker/midi), "PSID" or "RSID" a C64 SID tune (tracker/sid).
; The song it makes is added to a song file, after its songs, as :w
; writes one; a file with a song of that name already is refused, so an
; import never takes a song's place.

(module tracker/import)

(import x/sys/file)
(import x/core/doors int/ int% str-byte-ref char->int str-make)
(import tracker/song song-name)
(import tracker/file file-read file-songs file-add-song file-write!)
(import tracker/midi midi-song)
(import tracker/sid sid-song)

(def %im-fail (fn (_ what) (Err raise (lit value) (Str8 append "x-tracker: " what) ())))

; The bytes of the file at PATH, (BUF 0 LEN).
(def import-bytes
  (fn (_ path)
    (unless (File exists? path) (%im-fail (Str8 append "no file " path)))
    (list (File read-all path) 0 (Assoc get (lit size) (File stat path)))))

; Whether REGION's bytes start with TAG's.
(def %im-starts?
  (fn (_ region tag)
    (if (< (List ref 2 region) (Str8 length tag)) #f
      (List all? (fn (_ k) (= (char->int (str-byte-ref (first region) (+ (List ref 1 region) k))) (char->int (str-byte-ref tag k))))
        (List range 0 (Str8 length tag))))))

; The song REGION's bytes make, named NAME: a MIDI file's at ROWS rows a
; beat, a SID file's tune TUNE (0 the one it starts with) played for
; SECONDS, SAY nil or given lines of its progress.  Raises a label
; 'value for bytes no import reads.
(def import-song
  (fn (_ region name rows tune seconds say)
    (match ((%im-starts? region "MThd") (midi-song region name rows))
           ((if (%im-starts? region "PSID") #t (%im-starts? region "RSID")) (sid-song region name tune seconds say))
           (#t (%im-fail "not a file import reads: a MIDI file (.mid) or a SID file (.sid)")))))

; --- a SID tune's length -------------------------------------------------------
;
; HVSC's DOCUMENTS/Songlengths.md5 gives each tune's length by its file's
; MD5: a line "MD5=M:SS M:SS ..." (each may have ".MMM" and a "(X)" mark).
; It is looked for above the SID file, as a file in HVSC's C64Music is,
; and in $HVSC_BASE, the C64Music directory.

(def %im-db "DOCUMENTS/Songlengths.md5")

; The Songlengths.md5 for the file at PATH, or nil.
(def %im-songlengths
  (fn (_ path)
    (def parts (Str8 split "/" path))
    (def above (List map (fn (_ k) (Str8 append (Str8 join "/" (List take k parts)) "/" %im-db))
                 (List reverse (List range 1 (List length parts)))))
    (def base (Sys getenv "HVSC_BASE"))
    (List find (fn (_ p) (File exists? p))
      (List append above (if (null? base) () (list (Str8 append base "/" %im-db)))))))

; The rest of the line of the file at PATH that starts with KEY (KEY a
; line's start, its "\n" first), or nil: read 64 KiB at a time.
(def %im-line-of
  (fn (_ path key)
    (def fd (File open path 'rdonly))
    (if (< fd 0) ()
      (do (def buf (str-make 65536))
          (def line
            ((fn (self carry)
               (Heap collect)
               (def k (File read fd buf 65536))
               (def text (if (< 0 k) (Str8 append carry (Str8 sub 0 k buf)) carry))
               (def i (Str8 index-of key text))
               (def from (if (null? i) () (+ i (Str8 length key))))
               (def rest (if (null? from) () (Str8 sub from (- (Str8 length text) from) text)))
               (def end (if (null? rest) () (Str8 index-of "\n" rest)))
               (match ((not (null? end)) (Str8 sub 0 end rest))
                      ((< k 1) rest)
                      ((not (null? i)) (self (Str8 sub i (- (Str8 length text) i) text)))
                      (#t (self (Str8 sub (- (Str8 length text) (Str8 length key)) (Str8 length key) text)))))
             "\n"))
          (File close fd)
          line))))

; Whole seconds from TEXT, "M:SS" or "M:SS.MMM" with any "(X)" after, a
; part of one rounded up; nil for text that is none.
(def %im-clock
  (fn (_ text)
    (def bare (first (Str8 split "(" text)))
    (def ms (Str8 split ":" bare))
    (def ss (if (= 2 (List length ms)) (Str8 split "." (List ref 1 ms)) ()))
    (def num (fn (_ t) (guard (e ()) ((prim-ref (lit convert) (lit to)) t (Type named INTEGER) 10))))
    (def m (if (null? ss) () (num (first ms))))
    (def s (if (null? ss) () (num (first ss))))
    (def part (if (if (null? ss) #t (null? (rest ss))) 0 (num (List ref 1 ss))))
    (if (if (null? m) #t (if (null? s) #t (null? part))) ()
      (+ (* 60 m) (+ s (if (< 0 part) 1 0))))))

; The tune a SID file starts with, from its header in REGION.
(def %im-start
  (fn (_ region)
    ((fn (_ n) (if (< n 1) 1 n))
     (+ (* 256 (char->int (str-byte-ref (first region) (+ (List ref 1 region) 16))))
        (char->int (str-byte-ref (first region) (+ (List ref 1 region) 17)))))))

; The seconds HVSC gives tune TUNE (0 the one it starts with) of the SID
; file at PATH, REGION its bytes from 0: nil where it gives none.
(def import-sid-seconds
  (fn (_ path region tune)
    (def db (%im-songlengths path))
    (if (null? db) ()
      (do (import x/codec/md5)
          (def found (%im-line-of db (Str8 append "\n" (Md5 hex-n (first region) (List ref 2 region)) "=")))
          (def line (if (null? found) () (first (Str8 split "\r" found))))
          (def times (if (null? line) () (List filter (fn (_ t) (< 0 (Str8 length t))) (Str8 split " " line))))
          (def which (if (< 0 tune) tune (%im-start region)))
          (if (< (List length times) which) () (%im-clock (List ref (- which 1) times)))))))

; A song's name from PATH: its file's name, its extension left off.
(def import-name
  (fn (_ path)
    (def base (List last (Str8 split "/" path)))
    (def parts (Str8 split "." base))
    (if (if (< 1 (List length parts)) (not (str=? (first parts) "")) #f)
      (Str8 join "." (List take (- (List length parts) 1) parts))
      base)))

; The file at PATH imported into the song file OUT as the song NAME (the
; file's name when nil), ROWS, TUNE and SAY as import-song takes them,
; a SID tune played for SECONDS or, when nil, the length HVSC gives it
; (60 where it gives none): answers the song.  Raises a label 'value
; when OUT has a song NAME already.
(def import-file!
  (fn (_ path out name rows tune seconds say)
    (def nm (if (null? name) (import-name path) name))
    (def doc (file-read out))
    (when (List any? (fn (_ s) (str=? (song-name s) nm)) (file-songs doc))
      (%im-fail (Str8 append out " has a song " nm " already; -s NAME names the import")))
    (def region (import-bytes path))
    (def sid (if (%im-starts? region "PSID") #t (%im-starts? region "RSID")))
    (def known (if (if sid (null? seconds) #f) (import-sid-seconds path region tune) ()))
    (def secs (match ((not (null? seconds)) seconds) ((not (null? known)) known) (#t 60)))
    (when (if sid (null? seconds) #f)
      (unless (null? say)
        (say (if (null? known)
               "no length for the tune in HVSC's Songlengths.md5 (looked above the file and in $HVSC_BASE): playing 60 s; -t sets it"
               (Str8 append "HVSC gives the tune " (Str8 str (int/ known 60)) ":" (if (< (int% known 60) 10) "0" "") (Str8 str (int% known 60)))))))
    (def song (import-song region nm rows tune secs say))
    (file-write! (file-add-song doc song) out)
    song))

(provide tracker/import import-bytes import-song import-name import-sid-seconds import-file!)
