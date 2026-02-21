#!/bin/sh
":"; exec emacs --batch -L "$(dirname "$0")/.." --load "$0" "$@" # ;;; example-tesmut-generator.el --- Example: generate tests for basic Emacs mutations -*- lexical-binding: t; -*-

;; This example uses carettest-tesmut-generator to capture behavior of built-in
;; Emacs buffer-mutation commands on basic text, writing the result to
;; examples/generated-example-tests/.

   (require 'carettest-tesmut-generator)

(carettest-tesmut-generate-tests
 "The quick brown fox jumps over the lazy dog.
A second line with some more words here.
And a third line for extra coverage."
 10
 (list 'delete-char
    'backward-delete-char
       'kill-word
    'capitalize-word
       'upcase-word
    'downcase-word
       'transpose-chars
'("kill-2-words" (lambda () (kill-word 2))))
 "_generated-tesmut-example_.el"
 "example-tesmut"
 :dest-dir "examples/generated-example-tests"
 :set-mark-prob 0.2
 :transient-mark-mode-prob 0.8
 :generate-sequences nil
 :file-name-random-replacement t)
