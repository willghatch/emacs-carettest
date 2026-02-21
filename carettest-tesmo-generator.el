;;; carettest-tesmo-generator.el --- Generate random carettest-tesmo tests -*- lexical-binding: t; -*-

;; This file provides functions to automatically generate carettest-tesmo test cases
;; by running movement functions at random positions in test text.
;; IE this is a tool for making random tests that capture current behavior.

(require 'carettest-tesmo)

(defun carettest--tesmo-generator-random-string (length)
  "Generate a random string of LENGTH containing lowercase letters."
  (let ((chars "abcdefghijklmnopqrstuvwxyz")
        (result ""))
    (dotimes (_ length)
      (setq result (concat result (string (aref chars (random (length chars)))))))
    result))

(defun carettest--tesmo-generator-random-position (text)
  "Return a random valid position (0-based) in TEXT."
  (let ((max-pos (length text)))
    (if (= max-pos 0)
        0
      (random max-pos))))

(defun carettest--tesmo-generator-capture-movement (text start-pos movement-function &optional set-mark transient-mark-mode-val)
  "Capture the result of running MOVEMENT-FUNCTION at START-POS in TEXT.
Returns (start-pos end-pos mark-start-pos mark-end-pos success error-message).
If SET-MARK is non-nil, sets mark at a random position before movement.
TRANSIENT-MARK-MODE-VAL sets the transient-mark-mode during execution."
  (condition-case err
      (let ((old-transient-mark-mode transient-mark-mode))
        (setq transient-mark-mode (if (eq transient-mark-mode-val nil) nil t))  ; Default to t if not specified
        (unwind-protect
            (with-temp-buffer
              (insert text)
              (goto-char (1+ start-pos))  ; Convert to 1-based

              (let ((mark-start-pos nil)
                    (mark-end-pos nil))

                ;; Optionally set mark at random position
                (when set-mark
                  (let ((mark-pos (carettest--tesmo-generator-random-position text)))
                    (set-mark (1+ mark-pos))  ; Convert to 1-based
                    (activate-mark)
                    (setq mark-start-pos mark-pos)))

                ;; Execute movement function
                (if (functionp movement-function)
                    (funcall movement-function)
                  (call-interactively movement-function))

                ;; Capture end positions
                (let ((end-pos (1- (point)))  ; Convert back to 0-based
                      (mark-end (when (mark t) (1- (mark t)))))  ; Convert back to 0-based
                  (when mark-active
                    (setq mark-end-pos mark-end))

                  (list start-pos end-pos mark-start-pos mark-end-pos t nil))))
          ;; Restore transient-mark-mode
          (setq transient-mark-mode old-transient-mark-mode)))
    (error
     (list start-pos nil nil nil nil (error-message-string err)))))

(defun carettest--tesmo-generator-format-position-marker (pos text marker)
  "Insert MARKER at POS in TEXT, handling edge cases."
  (cond
   ((null pos) "")
   ((= pos 0) (concat marker text))
   ((>= pos (length text)) (concat text marker))
   (t (concat (substring text 0 pos) marker (substring text pos)))))

(defun carettest--tesmo-generator-create-carettest-tesmo-test (text start-pos end-pos mark-start-pos mark-end-pos
                                                                    movement-function test-name original-function
                                                                    &optional transient-mark-mode-val setup)
  "Create a tesmo test string from captured movement data.
If TRANSIENT-MARK-MODE-VAL is non-nil and not t, include :transient-mark-mode in the test."
  (let ((test-text text)
        (positions-to-insert '()))

    ;; Collect all positions and their markers, ensuring proper order
    ;; Point markers: <p0> for start, <p1> for end
    ;; Mark markers: <m0> for start, <m1> for end
    (when (and start-pos (>= start-pos 0) (<= start-pos (length text)))
      (push (list start-pos "<p0>" 1) positions-to-insert))
    (when (and end-pos (>= end-pos 0) (<= end-pos (length text)))
      (push (list end-pos "<p1>" 2) positions-to-insert))
    (when (and mark-start-pos (>= mark-start-pos 0) (<= mark-start-pos (length text)))
      (push (list mark-start-pos "<m0>" 3) positions-to-insert))
    (when (and mark-end-pos (>= mark-end-pos 0) (<= mark-end-pos (length text)))
      (push (list mark-end-pos "<m1>" 4) positions-to-insert))

    ;; Sort by position (descending), then by priority (ascending) to handle same positions
    (setq positions-to-insert
          (sort positions-to-insert
                (lambda (a b)
                  (let ((pos-a (car a))
                        (pos-b (car b))
                        (pri-a (nth 2 a))
                        (pri-b (nth 2 b)))
                    (if (= pos-a pos-b)
                        (< pri-a pri-b)  ; Same position: lower priority first
                      (> pos-a pos-b)))))) ; Different positions: higher position first

    ;; Insert markers from end to beginning to avoid position shifts
    (dolist (marker-info positions-to-insert)
      (let ((pos (car marker-info))
            (marker (cadr marker-info)))
        (setq test-text (concat (substring test-text 0 pos)
                                marker
                                (substring test-text pos)))))

    ;; Build the carettest-tesmo-test S-expression using proper data structures
    (let* ((movement-expr (cond
                           ((symbolp original-function)
                            `(quote ,original-function))
                           ((and (listp original-function) (eq (car original-function) 'lambda))
                            original-function)
                           ((and (listp original-function) (= (length original-function) 2)
                                 (not (eq (car original-function) 'lambda)))
                            ;; Handle (name function) format - use the actual function
                            (let ((actual-func (cadr original-function)))
                              (if (and (listp actual-func) (eq (car actual-func) 'lambda))
                                  actual-func
                                `(quote ,actual-func))))
                           (t
                            ;; For other functions, use the original form
                            original-function)))
           ;; Build the complete test expression as an S-expression
           (test-expr `(carettest-tesmo-test ,test-name
                                             ,test-text
                                             ,movement-expr
                                             :transient-mark-mode ,transient-mark-mode-val
                                             ,@(when setup `(:setup ,setup))
                                             :points ("<p0>" "<p1>")
                                             :marks ("<m0>" "<m1>"))))
      ;; Use pp-to-string to format the S-expression nicely
      (pp-to-string test-expr))))

(defun carettest--tesmo-generator-function-name (func)
  "Get a readable name for FUNC.
FUNC can be:
- A symbol (returns symbol-name)
- A lambda form (returns lambda-XXXX)
- A list of (name-string-or-symbol actual-function) (returns the name)"
  (cond
   ((symbolp func) (symbol-name func))
   ((and (listp func) (eq (car func) 'lambda))
    (format "lambda-%s" (carettest--tesmo-generator-random-string 4)))
   ((and (listp func) (= (length func) 2))
    ;; Handle (name function) format
    (let ((name (car func)))
      (if (symbolp name)
          (symbol-name name)
        (format "%s" name))))
   (t (format "func-%s" (carettest--tesmo-generator-random-string 4)))))

(defun carettest--tesmo-generate-tests (test-text num-positions movement-functions output-file test-prefix
                                                  set-mark-prob transient-mark-mode-setting &optional setup)
  "Generate random tesmo tests and write them to OUTPUT-FILE.

TEST-TEXT: Multi-line string to test movement functions on
NUM-POSITIONS: Number of random starting positions to try for each function
MOVEMENT-FUNCTIONS: List of movement functions to test. Each element can be:
  - A symbol (e.g. 'forward-word)
  - A lambda form (e.g. '(lambda () (forward-word 2)))
  - A list of (name function) for better closure naming (e.g. '(\"forward-2-words\" (lambda () (forward-word 2))))
OUTPUT-FILE: File to write generated tests to
TEST-PREFIX: Prefix for generated test names
SET-MARK-PROB: Probability (0.0-1.0) of setting mark before movement
TRANSIENT-MARK-MODE-SETTING: Value for transient-mark-mode during tests"
  (let ((generated-tests '())
        (test-count 0))

    ;; Generate tests for each movement function
    (dolist (movement-func movement-functions)
      (let* ((executable-func (cond
                               ;; Handle (name function) format
                               ((and (listp movement-func) (= (length movement-func) 2)
                                     (not (eq (car movement-func) 'lambda)))
                                (let ((actual-func (cadr movement-func)))
                                  (if (and (listp actual-func) (eq (car actual-func) 'lambda))
                                      (eval actual-func)  ; Convert lambda to executable closure
                                    actual-func)))        ; Use symbol as-is
                               ;; Handle direct lambda
                               ((and (listp movement-func) (eq (car movement-func) 'lambda))
                                (eval movement-func))     ; Convert lambda to executable closure
                               ;; Handle symbol
                               (t movement-func)))        ; Use symbol as-is
             (original-func-form movement-func))          ; Preserve original form for test code
        (dotimes (i num-positions)
          (let* ((start-pos (carettest--tesmo-generator-random-position test-text))
                 (set-mark (< (/ (float (random 100)) 100) set-mark-prob))
                 (result (carettest--tesmo-generator-capture-movement test-text start-pos executable-func set-mark transient-mark-mode-setting))
                 (success (nth 4 result)))

            (when (and success  ; Only generate test if movement succeeded
                       (or (not (eq start-pos (nth 1 result)))  ; Position changed
                           (and (nth 2 result) (nth 3 result))  ; Or mark was set/moved
                           (and (not (nth 2 result)) (not (nth 3 result)))))  ; Or no mark involved
              (let* ((end-pos (nth 1 result))
                     (mark-start-pos (nth 2 result))
                     (mark-end-pos (nth 3 result))
                     (func-name (carettest--tesmo-generator-function-name original-func-form))
                     (random-suffix (carettest--tesmo-generator-random-string 6))
                     (test-name (intern (format "%s-%s__%s" test-prefix func-name random-suffix)))
                     (test-code (carettest--tesmo-generator-create-carettest-tesmo-test
                                 test-text start-pos end-pos mark-start-pos mark-end-pos
                                 executable-func test-name original-func-form transient-mark-mode-setting setup)))
                (push test-code generated-tests)
                (setq test-count (1+ test-count))))))))

    ;; Write or append tests to file
    (let ((file-exists (file-exists-p output-file))
          (total-test-count test-count))

      (if file-exists
          ;; File exists, append tests
          (progn
            ;; Read existing file to get current test count
            (when (file-readable-p output-file)
              (with-temp-buffer
                (insert-file-contents output-file)
                (goto-char (point-min))
                (when (re-search-forward ";; Generated \\([0-9]+\\) tests" nil t)
                  (setq total-test-count (+ (string-to-number (match-string 1)) test-count)))))

            ;; Append new tests
            (with-temp-buffer
              (insert-file-contents output-file)

              ;; Update test count in header
              (goto-char (point-min))
              (when (re-search-forward ";; Generated \\([0-9]+\\) tests" nil t)
                (replace-match (format ";; Generated %d tests" total-test-count)))

              ;; Go to end of file and append new tests
              (goto-char (point-max))
              (unless (bolp) (insert "\n"))
              (insert "\n;; Additional tests generated on " (current-time-string) "\n\n")

              ;; Insert tests in reverse order so they appear in the original order
              (dolist (test (reverse generated-tests))
                (insert test "\n\n"))

              (write-region (point-min) (point-max) output-file)))

        ;; File doesn't exist, create new file
        (with-temp-file output-file
          (insert ";;; " (file-name-nondirectory output-file)
                  " --- Generated carettest-tesmo tests -*- lexical-binding: t; -*-\n\n")
          (insert ";; To run these tests from the command line:\n")
          (insert ";; emacs -batch -l ert -l carettest-tesmo.el -l "
                  (file-name-nondirectory output-file)
                  " -f ert-run-tests-batch-and-exit\n\n")
          (insert "(require 'carettest-tesmo)\n\n")
          (insert ";; Generated " (number-to-string test-count) " tests\n\n")

          ;; Insert tests in reverse order so they appear in the original order
          (dolist (test (reverse generated-tests))
            (insert test "\n\n"))))

      (message "Generated %d tests in %s (total: %d)" test-count output-file total-test-count)
      test-count)))

(defmacro carettest-tesmo-generate-tests (test-text num-positions movement-functions output-file test-prefix
                                                    &rest args)
  "Generate random tesmo tests and write them to OUTPUT-FILE.

This is a macro wrapper around `carettest--tesmo-generate-tests' that properly handles
default values for optional arguments.

TEST-TEXT: Multi-line string to test movement functions on
NUM-POSITIONS: Number of random starting positions to try for each function
MOVEMENT-FUNCTIONS: List of movement functions to test. Each element can be:
  - A symbol (e.g. 'forward-word)
  - A lambda form (e.g. '(lambda () (forward-word 2)))
  - A list of (name function) for better closure naming (e.g. '(\"forward-2-words\" (lambda () (forward-word 2))))
OUTPUT-FILE: File to write generated tests to (basename when :dest-dir is given)
TEST-PREFIX: Prefix for generated test names

Keyword arguments:
:dest-dir DIR - Directory to write OUTPUT-FILE into; created if absent (default nil)
:set-mark-prob PROB - Probability (0.0-1.0) of setting mark before movement (default 0.3)
:transient-mark-mode-prob PROB - Probability (0.0-1.0) that transient-mark-mode is enabled (default 1.0)
:setup FORM - Setup code to include in generated tests (default nil)
:file-name-random-replacement VAL - Controls random characters in the output file name (default nil).
  nil: no modification.
  A string: replace every occurrence of that string in OUTPUT-FILE with 6 random digits
    (e.g. :file-name-random-replacement \"RANDOM\" turns \"test-RANDOM.el\" into \"test-472938.el\").
  t: insert 6 random digits immediately before the final \".el\" suffix of OUTPUT-FILE
    (e.g. \"my-tests.el\" becomes \"my-tests472938.el\")."
  (let ((set-mark-prob 0.3)
        (transient-mark-mode-prob 1.0)
        (setup nil)
        (dest-dir nil)
        (file-name-random-replacement nil)
        (remaining-args args))

    ;; Parse keyword arguments
    (while remaining-args
      (pcase (pop remaining-args)
        (:dest-dir (setq dest-dir (pop remaining-args)))
        (:set-mark-prob (setq set-mark-prob (pop remaining-args)))
        (:transient-mark-mode-prob (setq transient-mark-mode-prob (pop remaining-args)))
        (:setup (setq setup (pop remaining-args)))
        (:file-name-random-replacement (setq file-name-random-replacement (pop remaining-args)))
        (other (error "Unknown keyword argument: %s" other))))

    ;; Determine transient-mark-mode value based on probability
    (let* ((transient-mark-mode-val (if (< (random 100) (* transient-mark-mode-prob 100)) t nil))
           (random-digits (format "%06d" (random 1000000)))
           (modified-output-file
            (cond
             ((null file-name-random-replacement) output-file)
             ((eq file-name-random-replacement t)
              (if (and (stringp output-file) (string-suffix-p ".el" output-file))
                  (concat (substring output-file 0 (- (length output-file) 3))
                          random-digits ".el")
                output-file))
             ((stringp file-name-random-replacement)
              (if (stringp output-file)
                  (replace-regexp-in-string
                   (regexp-quote file-name-random-replacement)
                   random-digits output-file t t)
                output-file))
             (t output-file)))
           (effective-output-file (if dest-dir
                                      `(progn
                                         (make-directory ,dest-dir t)
                                         (expand-file-name ,modified-output-file ,dest-dir))
                                    modified-output-file)))
      `(carettest--tesmo-generate-tests ,test-text ,num-positions ,movement-functions
                                        ,effective-output-file ,test-prefix
                                        ,set-mark-prob ,transient-mark-mode-val ,setup))))

(defun carettest-tesmo-generate-simple-tests ()
  "Generate some simple example test files for demonstration."
  (interactive)

  ;; Test 1: Basic word movement
  (carettest-tesmo-generate-tests
   "The quick brown fox jumps over the lazy dog"
   10
   '(forward-word backward-word forward-char backward-char)
   "__testing_cpo_tesmo_generator_1.el"
   "test-basic")

  ;; Test 2: Line movement with multiline text
  (carettest-tesmo-generate-tests
   "First line of text\nSecond line here\nThird line with more words\nFourth and final line"
   8
   '(beginning-of-line end-of-line forward-line backward-line)
   "__testing_cpo_tesmo_generator_2.el"
   "test-lines")

  ;; Test 3: Buffer movement
  (carettest-tesmo-generate-tests
   "Start of buffer\nMiddle content\nEnd of buffer"
   5
   '(beginning-of-buffer end-of-buffer)
   "__testing_cpo_tesmo_generator_3.el"
   "test-buffer"
   :transient-mark-mode-prob 0.0) ; Never enable transient-mark-mode

  ;; Test 4: Mixed movements with higher mark probability
  (carettest-tesmo-generate-tests
   "Hello world! This is a test string.\nWith multiple lines for testing.\nAnd punctuation, too!"
   15
   '(forward-word backward-word forward-sentence backward-sentence)
   "__testing_cpo_tesmo_generator_4.el"
   "test-mixed"
   :set-mark-prob 0.7) ; 70% chance of setting mark

  ;; Test 5: Lambda functions with better names (demonstrates new naming feature)
  (carettest-tesmo-generate-tests
   "One two three four five six seven eight nine ten"
   12
   (list 'forward-word
         'backward-word
         '("forward-word-2" (lambda () (forward-word 2)))
         '("backward-word-2" (lambda () (backward-word 2)))
         '("forward-char-5" (lambda () (forward-char 5)))
         '("backward-char-3" (lambda () (backward-char 3))))
   "__testing_cpo_tesmo_generator_5.el"
   "test-lambda"))

(defmacro carettest-tesmo-generate-tests-batch (functions output-file base-test-prefix &rest test-inputs)
  "Generate multiple test suites using the same function list but different test inputs.
All tests will be written to the same output file, with subsequent calls appending to the file.

FUNCTIONS: List of movement functions to test
OUTPUT-FILE: File to write all generated tests to (tests will be appended if file exists)
BASE-TEST-PREFIX: Base prefix for test names (will be suffixed with input suffix or index)
TEST-INPUTS: List of test input specifications. Each element should be a plist with:
  :text STRING - The test text
  :positions NUM - Number of test positions
  :suffix STRING - Suffix for test name (optional)
  :set-mark-prob PROB - Probability of setting mark (optional, default 0.3)
  :transient-mark-mode-prob PROB - Probability of transient-mark-mode (optional, default 0.8)
  :setup FORM - Setup code (optional)

Example usage:
  (carettest-tesmo-generate-tests-batch
   '(forward-word backward-word)
   \"my-tests.el\"
   \"test-words\"
   (:text \"Hello world\" :positions 5 :suffix \"simple\")
   (:text \"Complex text with symbols\" :positions 8 :suffix \"complex\"))"
  (let ((all-tests '())
        (test-count 0))

    ;; Process each test input
    (dolist (input test-inputs)
      (let* ((text (plist-get input :text))
             (positions (plist-get input :positions))
             (suffix (plist-get input :suffix))
             (set-mark-prob (or (plist-get input :set-mark-prob) 0.3))
             (transient-mark-mode-prob (or (plist-get input :transient-mark-mode-prob) 0.8))
             (setup (plist-get input :setup))
             (test-name (if suffix
                            (format "%s-%s" base-test-prefix suffix)
                          (format "%s-%d" base-test-prefix test-count))))

        (when (and text positions)
          (push `(carettest-tesmo-generate-tests
                  ,text
                  ,positions
                  (quote ,functions)
                  ,output-file
                  ,test-name
                  :set-mark-prob ,set-mark-prob
                  :transient-mark-mode-prob ,transient-mark-mode-prob
                  ,@(when setup `(:setup ,setup)))
                all-tests)
          (setq test-count (1+ test-count)))))

    ;; Return a progn form with all the test generation calls
    `(progn ,@(reverse all-tests))))

(provide 'carettest-tesmo-generator)
