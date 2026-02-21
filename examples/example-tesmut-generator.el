;;; example-tesmut-generator.el --- Example: generate tests for basic Emacs mutations -*- lexical-binding: t; -*-

;; This example uses cpo-tesmut-generator to capture behavior of built-in
;; Emacs buffer-mutation commands on basic text, writing the result to
;; examples/generated-example-tests/.

(require 'cpo-tesmut-generator)

(let* ((this-dir (file-name-directory (or load-file-name buffer-file-name)))
       (out-dir (expand-file-name "generated-example-tests" this-dir))
       (out-file (expand-file-name "generated-tesmut-example.el" out-dir)))

  (make-directory out-dir t)

  (cpo-tesmut-generate-tests
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
   out-file
   "example-tesmut"
   :set-mark-prob 0.2
   :transient-mark-mode-prob 0.8
   :generate-sequences nil))
