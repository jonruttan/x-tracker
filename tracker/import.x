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
(import x/core/doors str-byte-ref char->int)
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
; SECONDS.  Raises a label 'value for bytes no import reads.
(def import-song
  (fn (_ region name rows tune seconds)
    (match ((%im-starts? region "MThd") (midi-song region name rows))
           ((if (%im-starts? region "PSID") #t (%im-starts? region "RSID")) (sid-song region name tune seconds))
           (#t (%im-fail "not a file import reads: a MIDI file (.mid) or a SID file (.sid)")))))

; A song's name from PATH: its file's name, its extension left off.
(def import-name
  (fn (_ path)
    (def base (List last (Str8 split "/" path)))
    (def parts (Str8 split "." base))
    (if (if (< 1 (List length parts)) (not (str=? (first parts) "")) #f)
      (Str8 join "." (List take (- (List length parts) 1) parts))
      base)))

; The file at PATH imported into the song file OUT as the song NAME (the
; file's name when nil), ROWS, TUNE and SECONDS as import-song takes
; them: answers the song.  Raises a label 'value when OUT has a song NAME
; already.
(def import-file!
  (fn (_ path out name rows tune seconds)
    (def nm (if (null? name) (import-name path) name))
    (def doc (file-read out))
    (when (List any? (fn (_ s) (str=? (song-name s) nm)) (file-songs doc))
      (%im-fail (Str8 append out " has a song " nm " already; -s NAME names the import")))
    (def song (import-song (import-bytes path) nm rows tune seconds))
    (file-write! (file-add-song doc song) out)
    song))

(provide tracker/import import-bytes import-song import-name import-file!)
