;;; test-carettest-tesmut.el --- Tests for the carettest-tesmut testing framework -*- lexical-binding: t; -*-

;; To run these tests from the command line:
;; emacs -batch -l ert -l carettest-tesmut.el -l test-carettest-tesmut.el -f ert-run-tests-batch-and-exit

(require 'carettest-tesmut)

;;; Basic buffer mutation tests that should pass

(carettest-tesmut-test test-insert-text-basic
                       :before "hello <p>world"
                       :after "hello X<p>world"
                       :function (lambda () (insert "X")))

(carettest-tesmut-test test-delete-char-basic
                       :before "hel<p>lo world"
                       :after "hel<p>o world"
                       :function (lambda () (delete-char 1)))

(carettest-tesmut-test test-backward-delete-char-basic
                       "hel<p>lo world"
                       "he<p>lo world"
                       (lambda () (backward-delete-char 1)))

(carettest-tesmut-test test-kill-word-basic
                       "hello <p>world test"
                       "hello <p> test"
                       (lambda () (kill-word 1)))

(carettest-tesmut-test test-yank-basic
                       "hello <p>world"
                       "hello text<p>world"
                       'yank
                       :setup (progn (kill-new "text") nil))

;;; Tests with mark (region operations)

(carettest-tesmut-test test-kill-region-basic
                       "hello <p>world<m> test"
                       "hello <p><m> test"
                       'kill-region)

(carettest-tesmut-test test-delete-region-basic
                       "hello <p>world<m> test"
                       "hello <p><m> test"
                       'delete-region)

(carettest-tesmut-test test-upcase-region
                       "hello <p>world<m> test"
                       "hello <p>WORLD<m> test"
                       'upcase-region)

(carettest-tesmut-test test-downcase-region
                       "hello <p>WORLD<m> test"
                       "hello <p>world<m> test"
                       'downcase-region)

;;; Tests with closures/lambdas

(carettest-tesmut-test test-insert-multiple-chars
                       "hello <p>world"
                       "hello XXX<p>world"
                       (lambda () (insert "XXX")))

(carettest-tesmut-test test-delete-multiple-chars
                       "hello<p>world"
                       "hel<p>world"
                       (lambda () (backward-delete-char 2)))

;;; Tests with setup code

(carettest-tesmut-test test-insert-with-setup
                       "hello <p>world"
                       "hello setup<p>world"
                       (lambda () (insert "setup")))

;;; Tests with custom markers

(carettest-tesmut-test test-custom-markers-insert
                       "hello |point|world"
                       "hello X|point|world"
                       (lambda () (insert "X"))
                       :point-marker "|point|")

(carettest-tesmut-test test-custom-markers-region
                       "hello |mark|world|point| test"
                       "hello |mark|WORLD|point| test"
                       'upcase-region
                       :point-marker "|point|"
                       :mark-marker "|mark|")

;;; Tests verifying tesmut catches errors

(ert-deftest test-insert-wrong-result ()
  "Verify that tesmut catches a wrong insertion result."
  (carettest-tesmut-test inner-insert-wrong-result
                         "hello <p>world"
                         "hello Y<p>world"
                         (lambda () (insert "X")))
  (let* ((inner-test (ert-get-test 'inner-insert-wrong-result))
         (result (ert-run-test inner-test)))
    (should (ert-test-failed-p result))))

(ert-deftest test-delete-wrong-result ()
  "Verify that tesmut catches a wrong deletion result."
  (carettest-tesmut-test inner-delete-wrong-result
                         "hello<p>world"
                         "hello<p>world"
                         'delete-char)
  (let* ((inner-test (ert-get-test 'inner-delete-wrong-result))
         (result (ert-run-test inner-test)))
    (should (ert-test-failed-p result))))

;;; Edge case tests

(carettest-tesmut-test test-empty-buffer-insert
                       "<p>"
                       "X<p>"
                       (lambda () (insert "X")))

(carettest-tesmut-test test-multiline-insert
                       "first line\n<p>second line"
                       "first line\nX<p>second line"
                       (lambda () (insert "X")))

(carettest-tesmut-test test-beginning-of-buffer-insert
                       "<p>hello world"
                       "X<p>hello world"
                       (lambda () (insert "X")))

(carettest-tesmut-test test-end-of-buffer-insert
                       "hello world<p>"
                       "hello worldX<p>"
                       (lambda () (insert "X")))

;;; Tests for carettest-tesmut-test (multi-step testing)

(carettest-tesmut-test test-insert-delete-sequence
	                     :buffer-states '("hello <p>world"
			                                  "hello X<p>world"
			                                  "hello X<p>orld")
	                     :functions '((lambda () (insert "X"))
			                              (lambda () (delete-char 1))))

(carettest-tesmut-test test-kill-yank-sequence
	                     :buffer-states '("hello <p>world test"
			                                  "hello <p> test"
			                                  "hello world<p> test")
	                     :functions '((lambda () (kill-word 1))
			                              yank))

(carettest-tesmut-test test-region-operations-sequence
	                     :buffer-states '("hello <p>WORLD<m> test"
			                                  "hello <p>world<m> test"
			                                  "hello <p><m> test")
	                     :functions '(downcase-region
			                              kill-region))

(carettest-tesmut-test test-multi-insert-sequence
	                     :buffer-states '("<p>text"
			                                  "A<p>text"
			                                  "AB<p>text"
			                                  "ABC<p>text")
	                     :functions '((lambda () (insert "A"))
			                              (lambda () (insert "B"))
			                              (lambda () (insert "C"))))

(carettest-tesmut-test test-should-mixed-between-mutations
                       "hello <p>world"
                       "hello XY<p>world"
                       (lambda ()
                         (insert "X")
                         (should (string= (buffer-string) "hello Xworld"))
                         (insert "Y")
                         (should (string= (buffer-string) "hello XYworld"))))

;;; Test verifying tesmut catches a sequence error

(ert-deftest test-sequence-wrong-result ()
  "Verify that tesmut catches a wrong result in a multi-step sequence."
  (carettest-tesmut-test inner-sequence-wrong-result
	                       :buffer-states '("hello <p>world"
			                                    "hello X<p>world"
			                                    "hello XY<p>world")
	                       :functions '((lambda () (insert "X"))
			                                (lambda () (insert "Z"))))
  (let* ((inner-test (ert-get-test 'inner-sequence-wrong-result))
         (result (ert-run-test inner-test)))
    (should (ert-test-failed-p result))))

;;; Tests for carettest-tesmut's error message format

(ert-deftest test-tesmut-error-message ()
  "Test that carettest-tesmut produces expected error messages."
  (carettest-tesmut-test inner-mutation-test
	                       "hello <p>world"
	                       "hello Y<p>world"
	                       (lambda () (insert "X")))
  (let* ((inner-test (ert-get-test 'inner-mutation-test))
         (result (ert-run-test inner-test)))
    (should (ert-test-failed-p result))
    (let* ((error-condition (ert-test-result-with-condition-condition result))
           (error-message (cadr error-condition)))
      (should (stringp error-message))
      (should (string-match "inner-mutation-test: Actual:" error-message))
      (should (string-match "Expected:" error-message))
      (should (string-match "hello X<p>world" error-message))
      (should (string-match "hello Y<p>world" error-message)))))

(ert-deftest test-tesmut-multiline-error-message ()
  "Test that carettest-tesmut handles multiline text in error messages correctly."
  (carettest-tesmut-test inner-multiline-mutation-test
	                       "line one\n<p>line two"
	                       "line one\nY<p>line two"
	                       (lambda () (insert "X")))
  (let* ((inner-test (ert-get-test 'inner-multiline-mutation-test))
         (result (ert-run-test inner-test)))
    (should (ert-test-failed-p result))
    (let* ((error-condition (ert-test-result-with-condition-condition result))
           (error-message (cadr error-condition)))
      (should (stringp error-message))
      (should (string-match "inner-multiline-mutation-test: Actual:" error-message))
      (should (string-match "Expected:" error-message)))))

(ert-deftest test-tesmut-mark-handling ()
  "Test that carettest-tesmut properly handles mark positions in results."
  (carettest-tesmut-test inner-mark-mutation-test
	                       "hello <m>world<p> test"
	                       "hello <m>WRONG<p> test"
	                       'upcase-region)
  (let* ((inner-test (ert-get-test 'inner-mark-mutation-test))
         (result (ert-run-test inner-test)))
    (should (ert-test-failed-p result))
    (let* ((error-condition (ert-test-result-with-condition-condition result))
           (error-message (cadr error-condition)))
      (should (stringp error-message))
      (should (string-match "inner-mark-mutation-test: Actual:" error-message))
      (should (string-match "hello <m>WORLD<p> test" error-message))
      (should (string-match "hello <m>WRONG<p> test" error-message)))))

(provide 'test-carettest-tesmut)
