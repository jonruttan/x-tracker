; # x-tracker -- a music tracker on x-lang
;
; ## tests/harness.x -- what the spec harness adds to the dialect
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; The bundle kit's generator writes tests/lib/harness.gen.x: the dialect
; bundle.xon declares, the bundle's lib/ on the import path, then this file.
(import tracker/base)
(import x/sys/gc)
; (Bundle root "tracker"): where the specs read the songs and docs from.
(import x/sys/bundle)

; Each line of TEXT written as a line of its own, so a spec's expected
; output can be the whole of it.
(def spec-lines
  (fn (_ text) (List for-each (fn (_ l) (display l) (display "\n")) (Str8 split "\n" text))))

; The editor's helpers: ROWS of SCREEN as text, right-trimmed and joined
; by newlines; ST drawn on SCREEN, the heap collected first, as the
; terminal's loop does; KEYS pressed in ST, a string's characters each a
; key, a symbol a key of its own.
(import x/tui/screen)
(import x/tui/style)
(import x/sys/file)
(import x/codec/xon)

(def spec-rows
  (fn (_ screen rows)
    (Str8 join "\n" (List map (fn (_ i) (Str8 trim-right (Screen row-text screen i))) rows))))

(def spec-draw!
  (fn (_ st screen)
    (Heap collect)
    (edit-draw! st screen)))

(def spec-keys!
  (fn (_ st keys)
    (List for-each
      (fn (_ k) (if (str? k) (List for-each (fn (_ i) (edit-key! st (Str8 sub i 1 k))) (List range 0 (Str8 length k)))
                  (edit-key! st k)))
      keys)))

; The song ST edits, as text.
(def spec-song (fn (_ st) (song-text (edit-song st))))

; A stand-in for Sdl's audio messages: a stream's bytes put on it and
; counted, played only as a spec says (spec-play!).
(import x/type/vector)
(import x/type/class)
(def spec-streams (Vector make 4 0))
(def spec-opened (Vector make 1 0))
(def-class SpecAudio ()
  (static
    (method audio-open (self rate chans)
      ((fn (_ n) (Vector set! 0 (+ n 1) spec-opened) n) (Vector ref 0 spec-opened)))
    (method audio-put! (self s buf n) (Vector set! s (+ (Vector ref s spec-streams) n) spec-streams) n)
    (method audio-queued (self s)
      (Vector ref s spec-streams))
    (method audio-clear! (self s) (Vector set! s 0 spec-streams) s)
    (method audio-close (self s) ())))
; The stand-in, its streams empty.
(def spec-front
  (fn (_)
    (Vector set! 0 0 spec-opened)
    (List for-each (fn (_ i) (Vector set! i 0 spec-streams)) (List range 0 4))
    SpecAudio))
(def spec-tune
  (song-parse "(song \"s\" (bpm 240) (rows 4)\n  (instrument a (wave sine) (env (0 0) (5 60) (100 0)) (release 20))\n  (pattern p (a \"C4 . E4 .\"))\n  (pattern q (a \"G4 . . .\"))\n  (order p q))"))

; N bytes of every stream of the stand-in played: the time a speaker
; takes over them passed.
(def spec-play!
  (fn (_ n)
    (List for-each (fn (_ i) (Vector set! i (if (< (Vector ref i spec-streams) n) 0 (- (Vector ref i spec-streams) n)) spec-streams))
      (List range 0 4))))

; A Standard MIDI File's bytes, (BUF 0 LEN): FORMAT, DIVISION ticks a
; beat, and TRACKS, each a list of events (DELTA BYTE ...), an end of
; track put after the last.
(import x/codec/bytes)
(import x/core/doors int/ int% char->int)
(def spec-vlq
  (fn (_ n) ((fn (self n acc) (if (= n 0) acc (self (int/ n 128) (pair (+ 128 (int% n 128)) acc)))) (int/ n 128) (list (int% n 128)))))
(def spec-u32 (fn (_ n) (list (int% (int/ n 16777216) 256) (int% (int/ n 65536) 256) (int% (int/ n 256) 256) (int% n 256))))
(def spec-midi
  (fn (_ format division tracks)
    (def chunk
      (fn (_ tr)
        (def body (List flat-map (fn (_ e) (List append (spec-vlq (first e)) (rest e))) (List append tr (list (list 0 255 47 0)))))
        (List append (list 77 84 114 107) (spec-u32 (List length body)) body)))
    (Bytes of-list
      (List append (list 77 84 104 100 0 0 0 6 0 format 0 (List length tracks) (int/ division 256) (int% division 256))
        (List flat-map chunk tracks)))))

; REGION's bytes written to the file PATH.
(def spec-write-bytes!
  (fn (_ path region)
    (def fd (File open path (list (lit wronly) (lit creat) (lit trunc)) 420))
    (File write fd (first region) (List ref 2 region))
    (File close fd)
    path))

; A PSID file's bytes, (BUF 0 LEN): MAGIC "PSID" or "RSID", its code
; CODE (a list of bytes) loaded at LOAD, started at INIT and called each
; frame at PLAY (0 for its interrupt's handler).
(def spec-sid
  (fn (_ magic load init play code)
    (def u16 (fn (_ n) (list (int/ n 256) (int% n 256))))
    (Bytes of-list
      (List append (List map (fn (_ k) (char->int (Str8 ref k magic))) (List range 0 4))
        (list 0 2 0 124) (u16 load) (u16 init) (u16 play) (list 0 1 0 1 0 0 0 0)
        (List repeat 96 0) (list 0 0 0 0 0 0)
        code))))
