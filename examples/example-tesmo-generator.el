;;; example-tesmo-generator.el --- Example: generate tests for basic Emacs movements -*- lexical-binding: t; -*-

;; This example uses cpo-tesmo-generator to capture behavior of built-in
;; Emacs movement commands on basic text, writing the result to
;; examples/generated-example-tests/.

(require 'cpo-tesmo-generator)

(let* ((this-dir (file-name-directory (or load-file-name buffer-file-name)))
       (out-dir (expand-file-name "generated-example-tests" this-dir))
       (out-file (expand-file-name "generated-tesmo-example.el" out-dir)))

  (make-directory out-dir t)

  (cpo-tesmo-generate-tests
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
   out-file
   "example-tesmo"
   :set-mark-prob 0.3
   :transient-mark-mode-prob 0.8))
