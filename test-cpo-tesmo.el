;;; test-cpo-tesmo.el --- Tests for the cpo-tesmo testing framework -*- lexical-binding: t; -*-

;; To run these tests from the command line:
;; emacs -batch -l ert -l cpo-tesmo.el -l test-cpo-tesmo.el -f ert-run-tests-batch-and-exit

(require 'cpo-tesmo)

;;; Basic movement tests that should pass

(cpo-tesmo-test test-forward-word-basic
            "hello <p0>world<p1> test"
            'forward-word)

(cpo-tesmo-test test-backward-word-basic
            "hello <p1>world<p0> test"
            'backward-word)

(cpo-tesmo-test test-forward-char-basic
            "hel<p0>l<p1>o world"
            'forward-char)

(cpo-tesmo-test test-backward-char-basic
            "hel<p1>l<p0>o world"
            'backward-char)
(cpo-tesmo-test test-beginning-of-line
            "<p1>hello <p0>world"
            'beginning-of-line)
(cpo-tesmo-test test-end-of-line
            "<p0>hello world<p1>"
            'end-of-line)

;;; Tests with mark (region selection)

(cpo-tesmo-test test-forward-word-with-mark
            "hello <m0><m1>world<p0> test<p1> more"
            'forward-word)
(cpo-tesmo-test test-mark-word-simple
            "hello <p0><p1><m0>word<m1> test"
            'mark-word)
(cpo-tesmo-test test-mark-word
            "hello <p0><p1><m0>word<m1> test"
            'mark-word)

;;; Tests with closures/lambdas

(cpo-tesmo-test test-forward-word-multiple
            "one <p0>two three<p1> four"
            (lambda () (forward-word 2)))
(cpo-tesmo-test test-forward-char-multiple
            "hel<p0>lo wo<p1>rld"
            (lambda () (forward-char 5)))

;;; Tests with setup code

(cpo-tesmo-test test-lisp-mode-forward-sexp
            "(<p0>foo<p1> bar) (baz)"
            'forward-sexp
            :setup (lisp-mode))

;;; Tests with custom markers

(cpo-tesmo-test test-custom-markers
            "text |start|here|end| more"
            'forward-word)

;;; Expected failure tests - these demonstrate tesmo catching errors
(cpo-tesmo-test test-forward-word-wrong-position
            "hello <p0>world <p1>test"
            'forward-word
            :expected-result :failed)

(cpo-tesmo-test test-mark-position-wrong
            "hello <m0>world<p0> test<p1> more<m1>"
            (lambda ()
              (set-mark (point))
              (forward-word 1))
            :expected-result :failed)

;;; Edge case tests

(cpo-tesmo-test test-empty-buffer
            "<p0><p1>"
            (lambda () (ignore)))  ; No-op movement

(cpo-tesmo-test test-multiline-movement
            "first line\n<p0>second<p1> line\nthird line"
            'forward-word)

(cpo-tesmo-test test-beginning-of-buffer
            "<p1>hello <p0>world"
            'beginning-of-buffer)

(cpo-tesmo-test test-end-of-buffer
            "<p0>hello world<p1>"
            'end-of-buffer)



;; Test the behavior of cpo-tesmo for mark end -- mark should not be active
(cpo-tesmo-test test-deactivate-mark
            "foo <m0>bar<p0><p1> baz"
            'deactivate-mark)
(cpo-tesmo-test test-deactivate-mark-failure
            "foo <m0><m1>bar<p0><p1> baz"
            'deactivate-mark
            :expected-result :failed)
(cpo-tesmo-test test-mark-left-over
            "foo <m0><m1>bar<p0><p1> baz"
            'ignore)
(cpo-tesmo-test test-mark-left-over-failure
            "foo <m0>bar<p0><p1> baz"
            'ignore
            :expected-result :failed)
(cpo-tesmo-test test-mark-no-activate-failure
            "foo <m1>bar<p0><p1> baz"
            'ignore
            :expected-result :failed)

;; Test that explicitly tests transient-mark-mode differences with a command that matters
;; Use beginning-of-buffer which sets mark to remember position
(cpo-tesmo-test test-transient-mark-mode-on-beginning-buffer
            "<p1>hello <p0>world"
            'beginning-of-buffer
            :transient-mark-mode t)

(cpo-tesmo-test test-transient-mark-mode-off-beginning-buffer
            "<p1>hello <p0>world"
            'beginning-of-buffer
            :transient-mark-mode nil
            :expected-result :failed)

;; Demonstrate transient-mark-mode argument working - both should behave the same way
(cpo-tesmo-test test-explicit-transient-mark-on
            "test <p0>text<p1> here"
            'forward-word
            :transient-mark-mode t)

(cpo-tesmo-test test-explicit-transient-mark-off
            "test <p0>text<p1> here"
            'forward-word
            :transient-mark-mode nil)





;;; Tests for cpo-tesmo's error message format

(ert-deftest test-tesmo-point-error-message ()
  "Test that cpo-tesmo produces expected point mismatch error messages."
  (cpo-tesmo-test inner-point-test
              "hello <p0>world <p1>test"
              'forward-word)
  (let* ((inner-test (ert-get-test 'inner-point-test))
         (result (ert-run-test inner-test)))
    (should (ert-test-failed-p result))
    (let* ((error-condition (ert-test-result-with-condition-condition result))
           (error-message (cadr error-condition)))
      (should (stringp error-message))
      (should (string-match "mismatch for point (<p1>):" error-message))
      (should (string-match "Expected.*pos" error-message))
      (should (string-match "Actual.*line" error-message))
      (should (string-match "line 1" error-message)))))

(ert-deftest test-tesmo-mark-error-message ()
  "Test that cpo-tesmo produces expected mark mismatch error messages.
This defines an inner test that will be run and fail, and it will produce the expected message."
  (cpo-tesmo-test inner-mark-test
              "text <m0>here<p0> and<p1> wrong-position<m1>"
              'forward-word)
  (let* ((inner-test (ert-get-test 'inner-mark-test))
         (result (ert-run-test inner-test)))
    (should (ert-test-failed-p result))
    ;; Check the error message contains mark-specific info
    (let* ((error-condition (ert-test-result-with-condition-condition result))
           (error-message (cadr error-condition)))
      (should (stringp error-message))
      (should (string-match "mismatch for mark (<m1>):" error-message))
      (should (string-match "Expected: text here and wrong-position<m1> " error-message))
      (should (string-match "Actual: text <m1>here and wrong-position" error-message)))))

(ert-deftest test-tesmo-mark-activity-error-message ()
  "Test that cpo-tesmo produces expected mark activity error messages."
  (cpo-tesmo-test inner-mark-activity-test
              "<p1>text <p0>here"
              'beginning-of-buffer
              :transient-mark-mode nil)
  (let* ((inner-test (ert-get-test 'inner-mark-activity-test))
         (result (ert-run-test inner-test)))
    (should (ert-test-failed-p result))
    (let* ((error-condition (ert-test-result-with-condition-condition result))
           (error-message (cadr error-condition)))
      (should (stringp error-message))
      (should (string-match "Expected mark to be inactive but it was active" error-message))
      (should (string-match "inner-mark-activity-test" error-message)))))

(ert-deftest test-tesmo-multiline-error-message ()
  "Test that cpo-tesmo handles multiline text in error messages correctly."
  (cpo-tesmo-test inner-multiline-test
              "line one\nline <p0>two\nline three\nline <p1>four"
              'forward-word)
  (let* ((inner-test (ert-get-test 'inner-multiline-test))
         (result (ert-run-test inner-test)))
    (should (ert-test-failed-p result))
    (let* ((error-condition (ert-test-result-with-condition-condition result))
           (error-message (cadr error-condition)))
      (should (stringp error-message))
      (should (string-match "mismatch for point (<p1>)" error-message))
      (should (string-match "Expected: line <p1>four" error-message))
      (should (string-match "Actual: line two<p1>" error-message)))))

(provide 'test-cpo-tesmo)
