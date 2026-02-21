#!/bin/sh
":"; exec emacs --batch -L "$(dirname "$0")/.." --load "$0" "$@" # ;;; example-tesmo-generator.el --- Example: generate tests for basic Emacs movements -*- lexical-binding: t; -*-

;; This example uses carettest-tesmo-generator to capture behavior of built-in
;; Emacs movement commands on basic text, writing the result to
;; examples/generated-example-tests/.

(require 'carettest-tesmo-generator)

(carettest-tesmo-generate-tests
 "The quick brown fox jumps over the lazy dog.
A second line with some more words here.

And a third line to test paragraph movement."
 10
 '(forward-word
   backward-word
   forward-char
   backward-char
   beginning-of-line
   end-of-line
   ("forward-word-2" (lambda () (forward-word 2)))
   ("backward-word-2" (lambda () (backward-word 2))))
 (format "_generated-tesmo-example-%s.el" (carettest--tesmo-generator-random-string 6))
 "example-tesmo"
 :dest-dir "examples/generated-example-tests"
 :set-mark-prob 0.3
 :transient-mark-mode-prob 0.8)
