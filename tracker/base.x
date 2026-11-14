; # x-tracker -- a music tracker on x-lang
;
; ## tracker/base.x -- what the entry and the specs reach
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)

(import tracker/node node-tokens node-read node-form? node-text node-parts node-head node-value)
(import tracker/song song-from-node song-parse song-new song-name song-items song-rename song-patterns song-pattern
  song-order song-prop song-instruments song-instrument-text song-waves song-set-pattern song-drop-pattern song-set-order
  song-set-prop song-set-instrument pattern-rows pattern-cell pattern-set-cell pattern-resize pattern-insert-row
  pattern-delete-row pattern-add-channel pattern-drop-channel song-form song-text song-cell-problem
  song-effects song-set-effect song-drop-effect song-copy-instrument song-rename-instrument song-drop-instrument
  song-instrument-uses song-rename-pattern pattern-set-instrument pattern-move-channel pattern-block pattern-paste
  pattern-map-block song-note-name cell-transpose cell-gain)
(import tracker/file file-parse file-text file-songs file-song! file-add-song file-drop-song file-changed? file-written
  file-waves file-wave file-set-wave file-read file-write!)
(import tracker/player player-open player-playing? player-mode player-start! player-stop! player-update!
  player-preview! player-pump! player-place player-over? player-queued player-tension! player-pace! player-close
  player-waves player-waves! player-wave? player-start-at! player-tension player-pace player-volume player-volume!
  player-hears? player-mute! player-solo! player-muted? player-soloed? player-unmute! player-loop! player-loop player-render!)
(import tracker/config config-default config-file config-read config-load config-set! config-set-text! config-get
  config-put! config-problems config-style config-key config-lines config-backup!)
(import tracker/help help-topics help-topic help-index help-on help-word help-key-actions help-commands)
(import tracker/edit edit-make edit-song edit-doc edit-quit? edit-message edit-message! edit-player edit-place
  edit-feed! edit-settle! edit-tick! edit-key! edit-draw!)
(import tracker/app app-edit app-play)
(import tracker/cli tracker-version tracker-options tracker-main)
