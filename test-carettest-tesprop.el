;;; test-carettest-tesprop.el --- Tests for the carettest-tesprop testing framework -*- lexical-binding: t; -*-

;; To run these tests from the command line:
;; emacs -batch -l ert -l carettest-tesprop.el -l test-carettest-tesprop.el -f ert-run-tests-batch-and-exit

(require 'carettest-tesprop)

;;; Basic property assertions that should pass

(carettest-tesprop test-point-only-basic
  "hello <p>world"
  (= (point) 7)
  (string= (buffer-string) "hello world"))

(carettest-tesprop test-point-and-mark-basic
  "hello <m>world<p> test"
  mark-active
  (= (point) 12)
  (= (mark) 7)
  (string= (buffer-string) "hello world test"))

;;; Tests with setup and custom markers

(carettest-tesprop test-setup-inserts-text
  "hello <p>world"
  :setup (insert "X")
  (= (point) 8)
  (string= (buffer-string) "hello Xworld"))

(carettest-tesprop test-custom-markers-tesprop
  "hello |mark|world|point| test"
  :point-marker "|point|"
  :mark-marker "|mark|"
  mark-active
  (= (point) 12)
  (= (mark) 7)
  (string= (buffer-string) "hello world test"))

;;; Tests for the lower-level helper used inside ERT tests

(ert-deftest test-with-tesprop-buffer-basic ()
  "Verify that carettest-with-tesprop-buffer configures point and mark."
  (carettest-with-tesprop-buffer "hello <p>world<m> test"
    (should (= (point) 7))
    (should (= (mark) 12))
    (should mark-active)
    (should (string= (buffer-substring-no-properties (point-min) (point-max))
                     "hello world test"))))

(ert-deftest test-with-tesprop-buffer-setup ()
  "Verify that carettest-with-tesprop-buffer accepts setup forms."
  (carettest-with-tesprop-buffer "hello <p>world"
    :setup (insert "X")
    (should (= (point) 8))
    (should (string= (buffer-string) "hello Xworld"))))

;;; Tests verifying tesprop catches errors

(ert-deftest test-tesprop-failure ()
  "Verify that tesprop catches a wrong predicate."
  (carettest-tesprop inner-tesprop-failure
    "hello <p>world"
    (= (point) 999))
  (let* ((inner-test (ert-get-test 'inner-tesprop-failure))
         (result (ert-run-test inner-test)))
    (should (ert-test-failed-p result))))

(ert-deftest test-tesprop-duplicate-point-marker-error ()
  "Verify that tesprop rejects more than one point marker."
  (should-error
   (carettest-with-tesprop-buffer "hello <p>world<p>"
     (should t))))

(ert-deftest test-tesprop-duplicate-mark-marker-error ()
  "Verify that tesprop rejects more than one mark marker."
  (should-error
   (carettest-with-tesprop-buffer "hello <m>world<m><p>"
     (should t))))

(provide 'test-carettest-tesprop)
