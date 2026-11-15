; # x-tracker -- a music tracker on x-lang
;
; ## tracker/sid.x -- a C64 SID tune played and read into a song
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; A PSID or RSID file is a Commodore 64 program: 6502 code with an
; address to start a tune at and one to call each frame.  It is not
; read, it is run: a 6502 here runs the start, then the frame's call
; once a frame, and after each the SID's registers are taken down: each
; voice's frequency, waveform, pulse width, envelope and gate, and the
; filter.  A tune with no frame's call (an RSID's, a PSID's with play 0)
; has its interrupt's handler called instead, through $0314 or $FFFE.
; Nothing else of the machine is there: no VIC, no CIA but its timer's
; latch, no ROM but the end of the KERNAL's interrupt, so a tune that
; waits on the screen or reads the ROM may play wrong or not at all.
;
; The frames are then rows.  A row is as many frames as the notes'
; starts have in common (the frames between them), and a tick a frame,
; so a cell's effects run at the frame's pace: a note started off the
; row's first frame is delayed (/d), let go partway is cut (/c), a pitch
; that steps by semitones from frame to frame inside a row is an
; arpeggio (/a), and one that moves from row to row is a slide (/s).
; Each voice and sound is an instrument: its waveform (noise, pulse, saw
; or triangle, the first of them the voice has on), its pulse width at
; its first note, its attack, decay, sustain and release as an envelope,
; and the filter's cut-off when the voice goes through a low-pass.
; The song is cut into patterns of 64 rows (tracker/score).

(module tracker/sid)

(import x/type/vector)
(import x/core/doors int+ int- int* int/ int% int& int| int<< int>> int< int= obj-ref obj-set! str-byte-ref char->int)
(import tracker/song song-note-name)
(import tracker/score score-song)

(def %sd-fail (fn (_ what) (Err raise (lit value) (Str8 append "x-tracker: " what) ())))

; --- the machine -------------------------------------------------------------
;
; The CPU is a vector: 0 A, 1 X, 2 Y, 3 S, 4 PC, 5 C, 6 a value Z is set
; by (Z when it is 0), 7 one N is (its bit 7), 8 V, 9 D, 10 I, 11 the
; voices whose gate was written off this frame (a bit each), 12 the CIA
; timer's latch, 13 the raster line read, 14 the noise read at $D41B.
; Memory is a vector of 65536 bytes.

(def %r (fn (_ c k) (obj-ref c (int+ k 1))))
(def %w! (fn (_ c k v) (obj-set! c (int+ k 1) v) v))
(def %peek (fn (_ m a) (obj-ref m (int+ a 1))))
(def %poke! (fn (_ m a v) (obj-set! m (int+ a 1) v)))
(def %xor (fn (_ a b) (int- (int| a b) (int& a b))))

(def %io-rd
  (fn (_ c m a)
    (match ((int= a 0xD012) (%w! c 13 (int& (int+ (%r c 13) 1) 255)))
           ((int= a 0xD41B) (int& (int>> (%w! c 14 (int& (int+ (int* (%r c 14) 1103515245) 12345) 0x7FFFFFFF)) 16) 255))
           ((int= a 0xDC0D) 0)
           (#t (%peek m a)))))

(def %rd (fn (_ c m a) (if (int= (int>> a 12) 13) (%io-rd c m a) (%peek m a))))

(def %io-wr!
  (fn (_ c a v)
    (match ((if (int= a 0xD404) #t (if (int= a 0xD40B) #t (int= a 0xD412)))
             (when (int= (int& v 1) 0) (%w! c 11 (int| (%r c 11) (int<< 1 (int/ (int- a 0xD404) 7))))))
           ((int= a 0xDC04) (%w! c 12 (int| (int& (%r c 12) 0xFF00) v)))
           ((int= a 0xDC05) (%w! c 12 (int| (int& (%r c 12) 255) (int<< v 8))))
           (#t ()))))

(def %wr! (fn (_ c m a v) (when (int= (int>> a 12) 13) (%io-wr! c a v)) (%poke! m a v)))

(def %nz! (fn (_ c v) (%w! c 6 v) (%w! c 7 v) v))

; The status byte, B its break bit.
(def %p
  (fn (_ c b)
    (int| (int| (int| (int& (%r c 7) 128) (int<< (%r c 8) 6)) (int| 32 (int<< b 4)))
          (int| (int| (int<< (%r c 9) 3) (int<< (%r c 10) 2)) (int| (if (int= (%r c 6) 0) 2 0) (%r c 5))))))

(def %p!
  (fn (_ c p)
    (%w! c 7 (int& p 128)) (%w! c 8 (int& (int>> p 6) 1)) (%w! c 9 (int& (int>> p 3) 1))
    (%w! c 10 (int& (int>> p 2) 1)) (%w! c 6 (if (int= (int& p 2) 0) 1 0)) (%w! c 5 (int& p 1))))

(def %push! (fn (_ c m v) (%poke! m (int+ 256 (%r c 3)) v) (%w! c 3 (int& (int- (%r c 3) 1) 255))))
(def %pull (fn (_ c m) (%peek m (int+ 256 (%w! c 3 (int& (int+ (%r c 3) 1) 255))))))

(def %fetch (fn (_ c m) ((fn (_ pc) (%w! c 4 (int& (int+ pc 1) 0xFFFF)) (%peek m pc)) (%r c 4))))
(def %fetch16 (fn (_ c m) ((fn (_ lo) (int| lo (int<< (%fetch c m) 8))) (%fetch c m))))
(def %word (fn (_ m a b) (int| (%peek m a) (int<< (%peek m b) 8))))

; --- addressing: each answers the address the operand is at ------------------

(def %imm (fn (_ c m) ((fn (_ pc) (%w! c 4 (int& (int+ pc 1) 0xFFFF)) pc) (%r c 4))))
(def %zp (fn (_ c m) (%fetch c m)))
(def %zpx (fn (_ c m) (int& (int+ (%fetch c m) (%r c 1)) 255)))
(def %zpy (fn (_ c m) (int& (int+ (%fetch c m) (%r c 2)) 255)))
(def %abs (fn (_ c m) (%fetch16 c m)))
(def %abx (fn (_ c m) (int& (int+ (%fetch16 c m) (%r c 1)) 0xFFFF)))
(def %aby (fn (_ c m) (int& (int+ (%fetch16 c m) (%r c 2)) 0xFFFF)))
(def %inx (fn (_ c m) ((fn (_ z) (%word m z (int& (int+ z 1) 255))) (int& (int+ (%fetch c m) (%r c 1)) 255))))
(def %iny (fn (_ c m) ((fn (_ z) (int& (int+ (%word m z (int& (int+ z 1) 255)) (%r c 2)) 0xFFFF)) (%fetch c m))))
(def %ind (fn (_ c m) ((fn (_ a) (%word m a (int| (int& a 0xFF00) (int& (int+ a 1) 255)))) (%fetch16 c m))))

; --- the operations ------------------------------------------------------------

(def %adc!
  (fn (_ c v)
    (def a (%r c 0))
    (def s (int+ (int+ a v) (%r c 5)))
    (%w! c 8 (if (int= (int& (int& (%xor a s) (%xor v s)) 128) 0) 0 1))
    (if (int= (%r c 9) 0)
      (do (%w! c 5 (if (int< 255 s) 1 0)) (%w! c 0 (%nz! c (int& s 255))))
      (do (def lo0 (int+ (int+ (int& a 15) (int& v 15)) (%r c 5)))
          (def lo (if (int< 9 lo0) (int+ lo0 6) lo0))
          (def hi0 (int+ (int+ (int>> a 4) (int>> v 4)) (if (int< 15 lo) 1 0)))
          (def hi (if (int< 9 hi0) (int+ hi0 6) hi0))
          (%nz! c (int& s 255))
          (%w! c 5 (if (int< 15 hi) 1 0))
          (%w! c 0 (int& (int| (int<< hi 4) (int& lo 15)) 255))))))

(def %sbc!
  (fn (_ c v)
    (def a (%r c 0))
    (def borrow (int- 1 (%r c 5)))
    (if (int= (%r c 9) 0) (%adc! c (%xor v 255))
      (do (def lo0 (int- (int- (int& a 15) (int& v 15)) borrow))
          (def hi0 (int- (int- (int>> a 4) (int>> v 4)) (if (int< lo0 0) 1 0)))
          (def s (int- (int- a v) borrow))
          (%w! c 8 (if (int= (int& (int& (%xor a v) (%xor a s)) 128) 0) 0 1))
          (%w! c 5 (if (int< s 0) 0 1))
          (%nz! c (int& s 255))
          (%w! c 0 (int& (int| (int<< (if (int< hi0 0) (int+ hi0 10) hi0) 4) (int& (if (int< lo0 0) (int+ lo0 10) lo0) 15)) 255))))))

(def %cmp! (fn (_ c r v) ((fn (_ d) (%w! c 5 (if (int< d 0) 0 1)) (%nz! c (int& d 255))) (int- r v))))

(def %asl (fn (_ c v) (%w! c 5 (int>> v 7)) (%nz! c (int& (int<< v 1) 255))))
(def %lsr (fn (_ c v) (%w! c 5 (int& v 1)) (%nz! c (int>> v 1))))
(def %rol (fn (_ c v) ((fn (_ r) (%w! c 5 (int>> v 7)) (%nz! c r)) (int& (int| (int<< v 1) (%r c 5)) 255))))
(def %ror (fn (_ c v) ((fn (_ r) (%w! c 5 (int& v 1)) (%nz! c r)) (int| (int>> v 1) (int<< (%r c 5) 7)))))

; A read-modify-write of the byte at EA by F, answering the byte written.
(def %rmw! (fn (_ c m ea f) ((fn (_ v) (%wr! c m ea v) v) (f c (%rd c m ea)))))

(def %branch!
  (fn (_ c m t)
    ((fn (_ o) (when t (%w! c 4 (int& (int+ (%r c 4) (if (int< o 128) o (int- o 256))) 0xFFFF)))) (%fetch c m))))

; --- the table -----------------------------------------------------------------

(def %ops (Vector make 256 (fn (_ c m) (%w! c 4 0))))
(def %op! (fn (_ code f) (Vector set! code f %ops)))
; An operation F on the address MODE answers, at each of CODES.
(def %ops! (fn (_ codes mode f) (List for-each (fn (_ k) (%op! k (fn (_ c m) (f c m (mode c m))))) codes)))

; The eight modes of a group's column, codes BASE + 1, 5, 9, D, 11, 15, 19, 1D.
(def %group (fn (_ base) (List map (fn (_ o) (int+ base o)) (list 1 5 9 13 17 21 25 29))))
(def %group-modes (list %inx %zp %imm %abs %iny %zpx %aby %abx))
(def %group! (fn (_ base f) (List for-each (fn (_ k) (%ops! (list (List ref k (%group base))) (List ref k %group-modes) f)) (List range 0 8))))
; The seven of the unofficial read-modify-write group: + 3, 7, F, 13, 17, 1B, 1F.
(def %rmw-group! (fn (_ base f) (List for-each (fn (_ k) (%ops! (list (int+ base (List ref k (list 3 7 15 19 23 27 31)))) (List ref k (list %inx %zp %abs %iny %zpx %aby %abx)) f)) (List range 0 7))))

(%group! 0 (fn (_ c m ea) (%w! c 0 (%nz! c (int| (%r c 0) (%rd c m ea))))))
(%group! 32 (fn (_ c m ea) (%w! c 0 (%nz! c (int& (%r c 0) (%rd c m ea))))))
(%group! 64 (fn (_ c m ea) (%w! c 0 (%nz! c (%xor (%r c 0) (%rd c m ea))))))
(%group! 96 (fn (_ c m ea) (%adc! c (%rd c m ea))))
(%group! 128 (fn (_ c m ea) (%wr! c m ea (%r c 0))))
(%op! 137 (fn (_ c m) (%imm c m)))
(%group! 160 (fn (_ c m ea) (%w! c 0 (%nz! c (%rd c m ea)))))
(%group! 192 (fn (_ c m ea) (%cmp! c (%r c 0) (%rd c m ea))))
(%group! 224 (fn (_ c m ea) (%sbc! c (%rd c m ea))))
(%ops! (list 235) %imm (fn (_ c m ea) (%sbc! c (%rd c m ea))))

(%ops! (list 162) %imm (fn (_ c m ea) (%w! c 1 (%nz! c (%rd c m ea)))))
(%ops! (list 166) %zp (fn (_ c m ea) (%w! c 1 (%nz! c (%rd c m ea)))))
(%ops! (list 174) %abs (fn (_ c m ea) (%w! c 1 (%nz! c (%rd c m ea)))))
(%ops! (list 182) %zpy (fn (_ c m ea) (%w! c 1 (%nz! c (%rd c m ea)))))
(%ops! (list 190) %aby (fn (_ c m ea) (%w! c 1 (%nz! c (%rd c m ea)))))
(%ops! (list 160) %imm (fn (_ c m ea) (%w! c 2 (%nz! c (%rd c m ea)))))
(%ops! (list 164) %zp (fn (_ c m ea) (%w! c 2 (%nz! c (%rd c m ea)))))
(%ops! (list 180) %zpx (fn (_ c m ea) (%w! c 2 (%nz! c (%rd c m ea)))))
(%ops! (list 172) %abs (fn (_ c m ea) (%w! c 2 (%nz! c (%rd c m ea)))))
(%ops! (list 188) %abx (fn (_ c m ea) (%w! c 2 (%nz! c (%rd c m ea)))))
(%ops! (list 134) %zp (fn (_ c m ea) (%wr! c m ea (%r c 1))))
(%ops! (list 150) %zpy (fn (_ c m ea) (%wr! c m ea (%r c 1))))
(%ops! (list 142) %abs (fn (_ c m ea) (%wr! c m ea (%r c 1))))
(%ops! (list 132) %zp (fn (_ c m ea) (%wr! c m ea (%r c 2))))
(%ops! (list 148) %zpx (fn (_ c m ea) (%wr! c m ea (%r c 2))))
(%ops! (list 140) %abs (fn (_ c m ea) (%wr! c m ea (%r c 2))))
(%ops! (list 224) %imm (fn (_ c m ea) (%cmp! c (%r c 1) (%rd c m ea))))
(%ops! (list 228) %zp (fn (_ c m ea) (%cmp! c (%r c 1) (%rd c m ea))))
(%ops! (list 236) %abs (fn (_ c m ea) (%cmp! c (%r c 1) (%rd c m ea))))
(%ops! (list 192) %imm (fn (_ c m ea) (%cmp! c (%r c 2) (%rd c m ea))))
(%ops! (list 196) %zp (fn (_ c m ea) (%cmp! c (%r c 2) (%rd c m ea))))
(%ops! (list 204) %abs (fn (_ c m ea) (%cmp! c (%r c 2) (%rd c m ea))))
(def %bit! (fn (_ c m ea) ((fn (_ v) (%w! c 6 (int& (%r c 0) v)) (%w! c 7 v) (%w! c 8 (int& (int>> v 6) 1))) (%rd c m ea))))
(%ops! (list 36) %zp %bit!)
(%ops! (list 44) %abs %bit!)

; The shifts and steps of memory, and of A.
(def %shift! (fn (_ codes f) (%ops! (list (List ref 0 codes)) %zp (fn (_ c m ea) (%rmw! c m ea f)))
                             (%ops! (list (List ref 1 codes)) %zpx (fn (_ c m ea) (%rmw! c m ea f)))
                             (%ops! (list (List ref 2 codes)) %abs (fn (_ c m ea) (%rmw! c m ea f)))
                             (%ops! (list (List ref 3 codes)) %abx (fn (_ c m ea) (%rmw! c m ea f)))))
(%shift! (list 6 22 14 30) %asl)
(%shift! (list 70 86 78 94) %lsr)
(%shift! (list 38 54 46 62) %rol)
(%shift! (list 102 118 110 126) %ror)
(%shift! (list 230 246 238 254) (fn (_ c v) (%nz! c (int& (int+ v 1) 255))))
(%shift! (list 198 214 206 222) (fn (_ c v) (%nz! c (int& (int- v 1) 255))))
(%op! 10 (fn (_ c m) (%w! c 0 (%asl c (%r c 0)))))
(%op! 74 (fn (_ c m) (%w! c 0 (%lsr c (%r c 0)))))
(%op! 42 (fn (_ c m) (%w! c 0 (%rol c (%r c 0)))))
(%op! 106 (fn (_ c m) (%w! c 0 (%ror c (%r c 0)))))

; The registers and flags.
(%op! 232 (fn (_ c m) (%w! c 1 (%nz! c (int& (int+ (%r c 1) 1) 255)))))
(%op! 200 (fn (_ c m) (%w! c 2 (%nz! c (int& (int+ (%r c 2) 1) 255)))))
(%op! 202 (fn (_ c m) (%w! c 1 (%nz! c (int& (int- (%r c 1) 1) 255)))))
(%op! 136 (fn (_ c m) (%w! c 2 (%nz! c (int& (int- (%r c 2) 1) 255)))))
(%op! 170 (fn (_ c m) (%w! c 1 (%nz! c (%r c 0)))))
(%op! 168 (fn (_ c m) (%w! c 2 (%nz! c (%r c 0)))))
(%op! 138 (fn (_ c m) (%w! c 0 (%nz! c (%r c 1)))))
(%op! 152 (fn (_ c m) (%w! c 0 (%nz! c (%r c 2)))))
(%op! 186 (fn (_ c m) (%w! c 1 (%nz! c (%r c 3)))))
(%op! 154 (fn (_ c m) (%w! c 3 (%r c 1))))
(%op! 24 (fn (_ c m) (%w! c 5 0)))
(%op! 56 (fn (_ c m) (%w! c 5 1)))
(%op! 88 (fn (_ c m) (%w! c 10 0)))
(%op! 120 (fn (_ c m) (%w! c 10 1)))
(%op! 216 (fn (_ c m) (%w! c 9 0)))
(%op! 248 (fn (_ c m) (%w! c 9 1)))
(%op! 184 (fn (_ c m) (%w! c 8 0)))
(%op! 234 (fn (_ c m) 0))
(%op! 72 (fn (_ c m) (%push! c m (%r c 0))))
(%op! 104 (fn (_ c m) (%w! c 0 (%nz! c (%pull c m)))))
(%op! 8 (fn (_ c m) (%push! c m (%p c 1))))
(%op! 40 (fn (_ c m) (%p! c (%pull c m))))

; Branches, jumps and returns.
(%op! 16 (fn (_ c m) (%branch! c m (int= (int& (%r c 7) 128) 0))))
(%op! 48 (fn (_ c m) (%branch! c m (not (int= (int& (%r c 7) 128) 0)))))
(%op! 80 (fn (_ c m) (%branch! c m (int= (%r c 8) 0))))
(%op! 112 (fn (_ c m) (%branch! c m (int= (%r c 8) 1))))
(%op! 144 (fn (_ c m) (%branch! c m (int= (%r c 5) 0))))
(%op! 176 (fn (_ c m) (%branch! c m (int= (%r c 5) 1))))
(%op! 208 (fn (_ c m) (%branch! c m (not (int= (%r c 6) 0)))))
(%op! 240 (fn (_ c m) (%branch! c m (int= (%r c 6) 0))))
(%op! 76 (fn (_ c m) (%w! c 4 (%abs c m))))
(%op! 108 (fn (_ c m) (%w! c 4 (%ind c m))))
(%op! 32 (fn (_ c m) ((fn (_ to) (def back (int& (int- (%r c 4) 1) 0xFFFF)) (%push! c m (int>> back 8)) (%push! c m (int& back 255)) (%w! c 4 to)) (%abs c m))))
(%op! 96 (fn (_ c m) ((fn (_ lo) (%w! c 4 (int& (int+ (int| lo (int<< (%pull c m) 8)) 1) 0xFFFF))) (%pull c m))))
(%op! 64 (fn (_ c m) (%p! c (%pull c m)) ((fn (_ lo) (%w! c 4 (int| lo (int<< (%pull c m) 8)))) (%pull c m))))

; The unofficial operations tunes use.
(%rmw-group! 0 (fn (_ c m ea) (%w! c 0 (%nz! c (int| (%r c 0) (%rmw! c m ea %asl))))))
(%rmw-group! 32 (fn (_ c m ea) (%w! c 0 (%nz! c (int& (%r c 0) (%rmw! c m ea %rol))))))
(%rmw-group! 64 (fn (_ c m ea) (%w! c 0 (%nz! c (%xor (%r c 0) (%rmw! c m ea %lsr))))))
(%rmw-group! 96 (fn (_ c m ea) (%adc! c (%rmw! c m ea %ror))))
(%rmw-group! 192 (fn (_ c m ea) (%cmp! c (%r c 0) (%rmw! c m ea (fn (_ c v) (int& (int- v 1) 255))))))
(%rmw-group! 224 (fn (_ c m ea) (%sbc! c (%rmw! c m ea (fn (_ c v) (int& (int+ v 1) 255))))))
(List for-each (fn (_ k) (%ops! (list (List ref k (list 163 167 175 179 183 191))) (List ref k (list %inx %zp %abs %iny %zpy %aby))
                           (fn (_ c m ea) (%w! c 1 (%w! c 0 (%nz! c (%rd c m ea)))))))
  (List range 0 6))
(List for-each (fn (_ k) (%ops! (list (List ref k (list 131 135 143 151))) (List ref k (list %inx %zp %abs %zpy))
                           (fn (_ c m ea) (%wr! c m ea (int& (%r c 0) (%r c 1))))))
  (List range 0 4))
(List for-each (fn (_ k) (%op! k (fn (_ c m) 0))) (list 26 58 90 122 218 250))
(%ops! (list 128 130 194 226) %imm (fn (_ c m ea) 0))
(%ops! (list 4 68 100) %zp (fn (_ c m ea) 0))
(%ops! (list 20 52 84 116 212 244) %zpx (fn (_ c m ea) 0))
(%ops! (list 12) %abs (fn (_ c m ea) 0))
(%ops! (list 28 60 92 124 220 252) %abx (fn (_ c m ea) 0))

; Instructions run from PC until it is 0, a return to no caller, or
; LIMIT of them: answers how many.
(def %run!
  (fn (_ c m limit)
    ((fn (self n)
       (if (if (int= (%r c 4) 0) #t (not (int< n limit))) n
         (do ((obj-ref %ops (int+ (%fetch c m) 1)) c m) (self (int+ n 1)))))
     0)))

; The routine at ADDR called with A, as JSR calls, returning to 0.
(def %call!
  (fn (_ c m addr a limit)
    (%w! c 0 a) (%push! c m 255) (%push! c m 255) (%w! c 4 addr)
    (%run! c m limit)))

; The interrupt's handler at ADDR, its registers pushed as the KERNAL's
; entry pushes them when KERNAL is true.
(def %irq!
  (fn (_ c m addr kernal limit)
    (%push! c m 0) (%push! c m 0) (%push! c m (%p c 0))
    (when kernal (do (%push! c m (%r c 0)) (%push! c m (%r c 1)) (%push! c m (%r c 2))))
    (%w! c 10 1) (%w! c 4 addr)
    (%run! c m limit)))

; --- the tune ------------------------------------------------------------------

(def %sd-byte (fn (_ buf i) (char->int (str-byte-ref buf i))))
(def %sd-u16 (fn (_ buf i) (+ (* 256 (%sd-byte buf i)) (%sd-byte buf (+ i 1)))))

; The SID's registers after a frame: a vector of the 25 from $D400 and
; the voices whose gate was written off during it.
(def %snapshot (fn (_ c m) (Vector from-list (List append (List map (fn (_ k) (%peek m (int+ 0xD400 k))) (List range 0 25)) (list (%r c 11))))))

; The frames of the tune in REGION, TUNE of its tunes (0 for the one it
; starts with), SECONDS long: (FRAME-US FRAMES), FRAMES a list of
; snapshots.
(def %sd-play
  (fn (_ region tune seconds)
    (def buf (first region))
    (def at (List ref 1 region))
    (def len (List ref 2 region))
    (def magic (List map (fn (_ k) (%sd-byte buf (+ at k))) (List range 0 4)))
    (def rsid (= (first magic) 82))
    (unless (if (< 0x76 len) (if (List includes? (first magic) (list 80 82)) (equal? (rest magic) (list 83 73 68)) #f) #f)
      (%sd-fail "not a SID file"))
    (def offset (%sd-u16 buf (+ at 6)))
    (def load0 (%sd-u16 buf (+ at 8)))
    (def load (if (= load0 0) (+ (%sd-byte buf (+ at offset)) (* 256 (%sd-byte buf (+ (+ at offset) 1)))) load0))
    (def from (+ at (+ offset (if (= load0 0) 2 0))))
    (def init0 (%sd-u16 buf (+ at 10)))
    (def init (if (= init0 0) load init0))
    (def play (%sd-u16 buf (+ at 12)))
    (def songs (%sd-at-least 1 (%sd-u16 buf (+ at 14))))
    (def start (%sd-at-least 1 (%sd-u16 buf (+ at 16))))
    (def which (if (< 0 tune) tune start))
    (when (< songs which) (%sd-fail (Str8 append "the SID file's tunes are 1 to " (Str8 str songs))))
    (def speed (+ (* 65536 (%sd-u16 buf (+ at 18))) (%sd-u16 buf (+ at 20))))
    (def cia (if rsid #f (not (= 0 (int& (int>> speed (- (if (< 32 which) 32 which) 1)) 1)))))
    (def ntsc (if (< 0x7B offset) (= (int& (int>> (%sd-u16 buf (+ at 0x76)) 2) 3) 2) #f))
    (def m (Vector make 65536 0))
    (List for-each (fn (_ k) (when (< (+ load k) 65536) (%poke! m (+ load k) (%sd-byte buf (+ from k)))))
      (List range 0 (- (+ at len) from)))
    (List for-each (fn (_ base) (when (= 0 (%peek m base)) (List for-each (fn (_ k) (%poke! m (+ base k) (List ref k (list 104 168 104 170 104 64)))) (List range 0 6))))
      (list 0xEA31 0xEA81))
    (%poke! m 1 0x37)
    (def c (Vector make 15 0))
    (%w! c 3 255) (%w! c 6 1) (%w! c 14 1)
    (%call! c m init (- which 1) 2000000)
    (def kernal (not (= 0 (int& (%peek m 1) 2))))
    (def handler (if kernal (%word m 0x314 0x315) (%word m 0xFFFE 0xFFFF)))
    (def timer (%r c 12))
    (def frame-us (match ((if (if cia #t (if rsid (= play 0) #f)) (< 0 timer) #f) (int/ (* timer 1000000) 985248))
                         (cia 16667)
                         (ntsc 16667)
                         (#t 20000)))
    (def frames (int/ (* seconds 1000000) frame-us))
    (list frame-us
      (List map (fn (_ f)
                  (%w! c 11 0)
                  (if (= play 0) (%irq! c m handler kernal 200000) (%call! c m play 0 200000))
                  (%snapshot c m))
        (List range 0 frames)))))

(def %sd-at-least (fn (_ n x) (if (< x n) n x)))

; --- pitches -------------------------------------------------------------------

; The SID's frequency register for each semitone C0 to B7 (on PAL's clock).
(def %pitches
  (Vector from-list
    (List map (fn (_ s) (int/ (* (int<< (List ref (int% s 12) (list 16352 17324 18354 19445 20602 21827 23125 24500 25957 27500 29135 30868)) (int/ s 12)) 16777216) 985248000))
      (List range 0 96))))

; A frequency register's pitch, in cents above C0; nil for 0.
(def %cents
  (fn (_ f)
    (if (int< f 1) ()
      ((fn (self s)
         (if (if (int= s 95) #t (int< f (Vector ref (int+ s 1) %pitches)))
           ((fn (_ lo hi) (int+ (int* s 100) (if (int< f lo) 0 (int/ (int* 100 (int- f lo)) (int- hi lo)))))
            (Vector ref s %pitches) (Vector ref (if (int= s 95) 95 (int+ s 1)) %pitches))
           (self (int+ s 1))))
       0))))

; --- frames to rows --------------------------------------------------------------

(def %v-gate (fn (_ fr v) (int& (Vector ref (int+ (int* v 7) 4) fr) 1)))
(def %v-ctrl (fn (_ fr v) (Vector ref (int+ (int* v 7) 4) fr)))
(def %v-freq (fn (_ fr v) (int| (Vector ref (int* v 7) fr) (int<< (Vector ref (int+ (int* v 7) 1) fr) 8))))
(def %v-wave
  (fn (_ ctrl)
    (match ((int< 0 (int& ctrl 128)) "noise") ((int< 0 (int& ctrl 64)) "pulse") ((int< 0 (int& ctrl 32)) "saw")
           ((int< 0 (int& ctrl 16)) "triangle") (#t ()))))

; Whether voice V starts a note in frame F of FRAMES (a vector), its gate
; on and either off the frame before or written off in between.
(def %rise?
  (fn (_ frames f v)
    (def fr (Vector ref f frames))
    (if (int= (%v-gate fr v) 0) #f
      (if (null? (%v-wave (%v-ctrl fr v))) #f
        (if (int< 0 (int& (%v-ctrl fr v) 8)) #f
          (if (int= f 0) #t
            (if (int= (%v-gate (Vector ref (int- f 1) frames) v) 0) #t
              (not (int= 0 (int& (Vector ref 25 fr) (int<< 1 v)))))))))))

(def %gcd (fn (self a b) (if (int= b 0) a (self b (int% a b)))))

; The envelope's times: attack, and decay or release, in ms.
(def %attack-ms (list 2 8 16 24 38 56 68 80 100 250 500 800 1000 3000 5000 8000))
(def %decay-ms (list 6 24 48 72 114 168 204 240 300 750 1500 2400 3000 9000 15000 24000))

; An instrument's props from voice V in frame FR.
(def %sd-props
  (fn (_ fr v)
    (def ctrl (%v-ctrl fr v))
    (def ad (Vector ref (int+ (int* v 7) 5) fr))
    (def sr (Vector ref (int+ (int* v 7) 6) fr))
    (def wave (%v-wave ctrl))
    (def a (List ref (int>> ad 4) %attack-ms))
    (def d (List ref (int& ad 15) %decay-ms))
    (def pw (int| (Vector ref (int+ (int* v 7) 2) fr) (int<< (int& (Vector ref (int+ (int* v 7) 3) fr) 15) 8)))
    (def lowpass (if (int< 0 (int& (Vector ref 23 fr) (int<< 1 v))) (int< 0 (int& (Vector ref 24 fr) 16)) #f))
    (def cutoff (int| (int& (Vector ref 21 fr) 7) (int<< (Vector ref 22 fr) 3)))
    (Str8 append "(wave " (if (str=? wave "noise") "noise" wave) ")"
      (if (str=? wave "pulse") (Str8 append " (width (0 " (Str8 str (%sd-at-least 1 (int/ (int* (int& pw 4095) 100) 4096))) "))") "")
      " (env (0 0) (" (Str8 str a) " 100) (" (Str8 str (int+ a d)) " " (Str8 str (int/ (int* (int>> sr 4) 100) 15)) "))"
      " (release " (Str8 str (List ref (int& sr 15) %decay-ms)) ")"
      (if lowpass (Str8 append " (cut " (Str8 str (int+ 5 (int/ (int* cutoff 95) 2047))) ")") ""))))

; The rows of voice V: (CELLS INSTRUMENTS) for frames F0, F0 + PER, ...,
; INSTRUMENTS the props of each note's in the order first heard, each
; cell's note named by its index among them as (INDEX . CELL).
(def %voice-rows
  (fn (_ frames n f0 per rows v)
    (def cells (Vector make rows "."))
    (def props (Vector make 1 ()))
    (def inst-of
      (fn (_ p) ((fn (_ i) (if (null? i) (do (Vector set! 0 (List append (Vector ref 0 props) (list p)) props) (int- (List length (Vector ref 0 props)) 1)) i))
                 (List index-of p (Vector ref 0 props)))))
    (def pitch (fn (_ f) (%cents (%v-freq (Vector ref f frames) v))))
    ; Per row: whether a note sounds, its base in cents, its pitch with its
    ; slides, the arpeggio playing, and whether the last row slid.
    ((fn (self r on base at arp slid)
       (when (int< r rows)
         (do (def f (int+ f0 (int* r per)))
             (def fs (List filter (fn (_ k) (int< k n)) (List range f (int+ f per))))
             (def rise (List find (fn (_ k) (%rise? frames k v)) fs))
             (def p0 (if (null? rise) () (pitch rise)))
             (def struck (not (null? p0)))
             (def sounding (if struck #t (if (null? rise) on #f)))
             ; The frames the note is heard in: from its start to its gate off.
             (def from (List filter (fn (_ k) (if struck (not (int< k rise)) #t)) fs))
             (def fall (if sounding (List find (fn (_ k) (int= 0 (%v-gate (Vector ref k frames) v))) from) ()))
             (def heard (if (null? fall) from (List filter (fn (_ k) (int< k fall)) from)))
             (def cut (if (null? fall) "" (Str8 append "/c" (Str8 str (int- fall f)))))
             (def head
               (match (struck
                        (Str8 append (song-note-name (int/ (int+ p0 50) 100)) (if (int= rise f) "" (Str8 append "/d" (Str8 str (int- rise f)))) cut))
                      ((null? fall) ".")
                      ((int= fall f) "-")
                      (#t (Str8 append "." cut))))
             (def now-on (if sounding (null? fall) #f))
             (def now-base (if struck (int* 100 (int/ (int+ p0 50) 100)) base))
             (def now-at (if struck now-base at))
             (def was-arp (if struck () arp))
             (def was-slid (if struck #f slid))
             ; The pitches of the row's frames, in semitones from the note's base.
             (def steps (if now-on (List map (fn (_ k) ((fn (_ p) (if (null? p) 0 (int/ (int+ (int- p now-base) 1250) 100))) (pitch k))) heard) ()))
             (def offsets (List map (fn (_ s) (int- s 12)) steps))
             (def arpeggio (if (List any? (fn (_ o) (not (int= o (first offsets)))) offsets)
                             (List filter (fn (_ o) (not (int= o 0))) (List fold (fn (_ acc o) (if (List includes? o acc) acc (List append acc (list o)))) () offsets))
                             ()))
             (def next-p (if (int< (int+ f per) n) (pitch (int+ f per)) ()))
             (def slide (if (if now-on (if (null? arpeggio) (if (null? next-p) #f (not (int= 0 (%v-gate (Vector ref (int+ f per) frames) v)))) #f) #f)
                          ((fn (_ d) (if (int< (if (int< d 0) (int- 0 d) d) 10) 0 d)) (int- next-p now-at))
                          0))
             (def fx
               (Str8 append
                 (match ((not now-on) "")
                        ((not (null? arpeggio)) (if (equal? arpeggio was-arp) "" (Str8 append "/a" (Str8 join "," (List map (fn (_ o) (Str8 str o)) arpeggio)))))
                        ((null? was-arp) "")
                        (#t "/a"))
                 (match ((not now-on) "") ((not (int= slide 0)) (Str8 append "/s" (Str8 str slide))) (was-slid "/s0") (#t ""))))
             (unless (if (str=? head ".") (str=? fx "") #f)
               (Vector set! r (if (not struck) (pair () (Str8 append head fx))
                                (pair (inst-of (%sd-props (Vector ref rise frames) v)) (Str8 append head fx)))
                 cells))
             (self (int+ r 1) now-on now-base (int+ now-at slide) (if now-on arpeggio ()) (not (int= slide 0))))))
     0 #f 0 0 () #f)
    (list cells (Vector ref 0 props))))

; The song a SID file makes: REGION (BUF START LEN) its bytes, NAME the
; song's name, TUNE which of its tunes (0 the one it starts with),
; SECONDS how long it is played.  Raises a label 'value for bytes that are
; no PSID or RSID file, or a tune with no notes.
(def sid-song
  (fn (_ region name tune seconds)
    (def played (%sd-play region tune seconds))
    (def frame-us (first played))
    (def frames (Vector from-list (List ref 1 played)))
    (def n (Vector length frames))
    (def rises (List flat-map (fn (_ v) (List filter (fn (_ f) (%rise? frames f v)) (List range 0 n))) (list 0 1 2)))
    (when (null? rises) (%sd-fail "the SID tune plays no notes"))
    (def sorted (List sort < rises))
    (def f0 (first sorted))
    (def g (List fold (fn (_ acc f) (%gcd acc (- f f0))) 0 sorted))
    (def per0 (if (= g 0) 6 g))
    (def per (List find (fn (_ d) (= 0 (int% per0 d))) (List reverse (List range 1 (+ 1 (if (< per0 16) per0 16))))))
    (def start (int% f0 per))
    (def rows (int/ (+ (- n start) (- per 1)) per))
    (def row-ms (int/ (+ (* per frame-us) 500) 1000))
    (def beat (List find (fn (_ k) ((fn (_ b) (if (< 0 b) (if (< b 1000) (= row-ms (int/ 60000 (* b k))) #f) #f)) (int/ 60000 (* k row-ms))))
                (list 4 3 6 8 2 5 1)))
    (def rpb (if (null? beat) 1 beat))
    (def bpm (%sd-at-least 1 (int/ 60000 (* rpb row-ms))))
    (def voices (List map (fn (_ v) (%voice-rows frames n start per rows v)) (list 0 1 2)))
    ; Each voice's instruments named for their wave and voice.
    (def named
      (List fold
        (fn (_ acc v)
          (List append acc
            (List map (fn (_ k)
                        (def p (List ref k (List ref 1 (List ref v voices))))
                        (def wave (Str8 sub 6 (- (Str8 index-of ")" p) 6) p))
                        (list v k (Str8 append wave (Str8 str (+ v 1)) (if (= k 0) "" (Str8 append "-" (Str8 str (+ k 1))))) p))
              (List range 0 (List length (List ref 1 (List ref v voices)))))))
        () (list 0 1 2)))
    (def inst-name (fn (_ v k) (List ref 2 (List find (fn (_ e) (if (= (first e) v) (= (List ref 1 e) k) #f)) named))))
    ; A channel an instrument of a voice: the voice's cells where that
    ; instrument plays, and where it does not, its let-go and holds.
    (def columns
      (List flat-map
        (fn (_ v)
          (def cells (first (List ref v voices)))
          (List map
            (fn (_ e)
              (def out (Vector make rows "."))
              ((fn (self r mine)
                 (when (< r rows)
                   ((fn (_ c)
                      (match ((str? c) (self (+ r 1) mine))
                             ((null? (first c)) (do (when mine (Vector set! r (rest c) out)) (self (+ r 1) mine)))
                             ((= (first c) (List ref 1 e)) (do (Vector set! r (rest c) out) (self (+ r 1) #t)))
                             (#t (do (when mine (Vector set! r "-" out)) (self (+ r 1) #f)))))
                    (Vector ref r cells))))
               0 #f)
              (list (List ref 2 e) #t out))
            (List filter (fn (_ e) (= (first e) v)) named)))
        (list 0 1 2)))
    (when (null? columns) (%sd-fail "the SID tune plays no notes"))
    (score-song name (Str8 append "(bpm " (Str8 str bpm) ") (rows " (Str8 str rpb) ") (ticks " (Str8 str per) ")\n  (limit 90 120)")
      (List map (fn (_ e) (Str8 append "(instrument " (List ref 2 e) " " (List ref 3 e) " (gain 35))")) named)
      columns (* 16 rpb))))

; CODE, a list of bytes, loaded at LOAD and called at ADDR, as a check of
; the 6502: answers (A X Y MEMORY), MEMORY a vector of its 65536 bytes.
(def sid-run
  (fn (_ code load addr)
    (def m (Vector make 65536 0))
    (List for-each (fn (_ k) (%poke! m (+ load k) (List ref k code))) (List range 0 (List length code)))
    (def c (Vector make 15 0))
    (%w! c 3 255) (%w! c 6 1)
    (%call! c m addr 0 100000)
    (list (%r c 0) (%r c 1) (%r c 2) m)))

(provide tracker/sid sid-song sid-run)
