;;; cpo-tesmut-generator.el --- Generate random cpo-tesmut tests -*- lexical-binding: t; -*-

;; This file provides functions to automatically generate cpo-tesmut test cases
;; by running mutation functions at random positions in test text.
;; IE this is a tool for making random tests that capture current behavior.

(require 'cpo-tesmut)

(defun cpo-tesmut-generator--random-string (length)
  "Generate a random string of LENGTH containing lowercase letters."
  (let ((chars "abcdefghijklmnopqrstuvwxyz")
        (result ""))
    (dotimes (_ length)
      (setq result (concat result (string (aref chars (random (length chars)))))))
    result))

(defun cpo-tesmut-generator--random-position (text)
  "Return a random valid position (0-based) in TEXT."
  (let ((max-pos (length text)))
    (if (= max-pos 0)
        0
      (random max-pos))))

(defun cpo-tesmut-generator--capture-mutation (text start-pos mutation-function &optional set-mark transient-mark-mode-val)
  "Capture the result of running MUTATION-FUNCTION at START-POS in TEXT.
Returns (before-text after-text success error-message).
If SET-MARK is non-nil, sets mark at a random position before mutation.
TRANSIENT-MARK-MODE-VAL sets the transient-mark-mode during execution."
  (condition-case err
      (let ((old-transient-mark-mode transient-mark-mode))
        (setq transient-mark-mode (if (eq transient-mark-mode-val nil) nil t))  ; Default to t if not specified
        (unwind-protect
            (with-temp-buffer
              (insert text)
              (goto-char (1+ start-pos))  ; Convert to 1-based

              ;; Optionally set mark at random position
              (when set-mark
                (let ((mark-pos (cpo-tesmut-generator--random-position text)))
                  (set-mark (1+ mark-pos))  ; Convert to 1-based
                  (activate-mark)))

              ;; Capture before state
              (let ((before-text (cpo-tesmut--buffer-to-string-with-markers "<p>" "<m>")))

                ;; Execute mutation function
                (if (functionp mutation-function)
                    (funcall mutation-function)
                  (call-interactively mutation-function))

                ;; Capture after state
                (let ((after-text (cpo-tesmut--buffer-to-string-with-markers "<p>" "<m>")))
                  (list before-text after-text t nil))))
          ;; Restore transient-mark-mode
          (setq transient-mark-mode old-transient-mark-mode)))
    (error
     (list nil nil nil (error-message-string err)))))

(defun cpo-tesmut-generator--create-cpo-tesmut-test (before-text after-text mutation-function test-name original-function
                                                         &optional transient-mark-mode-val setup)
  "Create a tesmut test string from captured mutation data."
  ;; Build the cpo-tesmut-test S-expression using proper data structures
  (let* ((function-expr (cond
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
         (test-expr `(cpo-tesmut-test ,test-name
                                  :before ,before-text
                                  :after ,after-text
                                  :function ,function-expr
                                  :transient-mark-mode ,transient-mark-mode-val
                                  ,@(when setup `(:setup ,setup)))))
    ;; Use pp-to-string to format the S-expression nicely
    (pp-to-string test-expr)))

(defun cpo-tesmut-generator--create-tesmut-sequence-test (buffer-states functions test-name original-functions
                                                                    &optional transient-mark-mode-val setup)
  "Create a cpo-tesmut-test string from captured sequence data."
  ;; Build the functions list using proper data structures
  (let* ((functions-list (mapcar (lambda (func)
                                   (cond
                                    ((symbolp func)
                                     `(quote ,func))
                                    ((and (listp func) (eq (car func) 'lambda))
                                     func)
                                    (t func)))
                                 original-functions))
         ;; Build the complete test expression as an S-expression
         (test-expr `(cpo-tesmut-test ,test-name
                                  :buffer-states (quote ,buffer-states)
                                  :functions (quote ,functions-list)
                                  :transient-mark-mode ,transient-mark-mode-val
                                  ,@(when setup `(:setup ,setup)))))
    ;; Use pp-to-string to format the S-expression nicely
    (pp-to-string test-expr)))

(defun cpo-tesmut-generator--function-name (func)
  "Get a readable name for FUNC.
FUNC can be:
- A symbol (returns symbol-name)
- A lambda form (returns lambda-XXXX)
- A list of (name-string-or-symbol actual-function) (returns the name)"
  (cond
   ((symbolp func) (symbol-name func))
   ((and (listp func) (eq (car func) 'lambda))
    (format "lambda-%s" (cpo-tesmut-generator--random-string 4)))
   ((and (listp func) (= (length func) 2))
    ;; Handle (name function) format
    (let ((name (car func)))
      (if (symbolp name)
          (symbol-name name)
        (format "%s" name))))
   (t (format "func-%s" (cpo-tesmut-generator--random-string 4)))))

(defun cpo-tesmut--generate-tests (test-text num-positions mutation-functions output-file test-prefix
                                         set-mark-prob transient-mark-mode-setting generate-sequences &optional setup)
  "Generate random tesmut tests and write them to OUTPUT-FILE.

TEST-TEXT: Multi-line string to test mutation functions on
NUM-POSITIONS: Number of random starting positions to try for each function
MUTATION-FUNCTIONS: List of mutation functions to test. Each element can be:
  - A symbol (e.g. 'insert)
  - A lambda form (e.g. '(lambda () (insert \"X\")))
  - A list of (name function) for better closure naming (e.g. '(\"insert-X\" (lambda () (insert \"X\"))))
  - For sequence tests: a list of functions for multi-step tests
OUTPUT-FILE: File to write generated tests to
TEST-PREFIX: Prefix for generated test names
SET-MARK-PROB: Probability (0.0-1.0) of setting mark before mutation
TRANSIENT-MARK-MODE-SETTING: Value for transient-mark-mode during tests
GENERATE-SEQUENCES: If non-nil, also generate sequence tests for lists of functions"
  (let ((generated-tests '())
        (test-count 0))

    ;; Generate tests for each mutation function
    (dolist (mutation-func mutation-functions)
      (cond
       ;; Handle sequence tests (list of functions)
       ((and generate-sequences (listp mutation-func) (not (eq (car mutation-func) 'lambda))
             (not (and (= (length mutation-func) 2) (not (listp (car mutation-func))))))
        ;; This is a list of functions for sequence testing
        (dotimes (i num-positions)
          (let* ((start-pos (cpo-tesmut-generator--random-position test-text))
                 (set-mark (< (/ (float (random 100)) 100) set-mark-prob))
                 (buffer-states (list))
                 (executable-funcs (list))
                 (original-funcs (list))
                 (success t))

            ;; Build executable functions list
            (dolist (func mutation-func)
              (let ((executable-func (cond
                                      ;; Handle (name function) format
                                      ((and (listp func) (= (length func) 2)
                                            (not (eq (car func) 'lambda)))
                                       (let ((actual-func (cadr func)))
                                         (if (and (listp actual-func) (eq (car actual-func) 'lambda))
                                             (eval actual-func)  ; Convert lambda to executable closure
                                           actual-func)))        ; Use symbol as-is
                                      ;; Handle direct lambda
                                      ((and (listp func) (eq (car func) 'lambda))
                                       (eval func))     ; Convert lambda to executable closure
                                      ;; Handle symbol
                                      (t func))))        ; Use symbol as-is
                (push executable-func executable-funcs)
                (push func original-funcs)))

            (setq executable-funcs (reverse executable-funcs))
            (setq original-funcs (reverse original-funcs))

            ;; Capture sequence of states
            (condition-case err
                (let ((old-transient-mark-mode transient-mark-mode))
                  (setq transient-mark-mode transient-mark-mode-setting)
                  (unwind-protect
                      (with-temp-buffer
                        (insert test-text)
                        (goto-char (1+ start-pos))  ; Convert to 1-based

                        ;; Optionally set mark at random position
                        (when set-mark
                          (let ((mark-pos (cpo-tesmut-generator--random-position test-text)))
                            (set-mark (1+ mark-pos))  ; Convert to 1-based
                            (activate-mark)))

                        ;; Capture initial state
                        (push (cpo-tesmut--buffer-to-string-with-markers "<p>" "<m>") buffer-states)

                        ;; Execute functions and capture states
                        (dolist (executable-func executable-funcs)
                          (if (functionp executable-func)
                              (funcall executable-func)
                            (call-interactively executable-func))
                          (push (cpo-tesmut--buffer-to-string-with-markers "<p>" "<m>") buffer-states)))
                    ;; Restore transient-mark-mode
                    (setq transient-mark-mode old-transient-mark-mode)))
              (error (setq success nil)))

            (when success
              (setq buffer-states (reverse buffer-states))
              (let* ((sequence-name (mapconcat #'cpo-tesmut-generator--function-name original-funcs "-"))
                     (random-suffix (cpo-tesmut-generator--random-string 6))
                     (test-name (intern (format "%s-seq-%s__%s" test-prefix sequence-name random-suffix)))
                     (test-code (cpo-tesmut-generator--create-tesmut-sequence-test
                                 buffer-states executable-funcs test-name original-funcs transient-mark-mode-setting setup)))
                (push test-code generated-tests)
                (setq test-count (1+ test-count)))))))

       ;; Handle single function tests
       (t
        (let* ((executable-func (cond
                                 ;; Handle (name function) format
                                 ((and (listp mutation-func) (= (length mutation-func) 2)
                                       (not (eq (car mutation-func) 'lambda)))
                                  (let ((actual-func (cadr mutation-func)))
                                    (if (and (listp actual-func) (eq (car actual-func) 'lambda))
                                        (eval actual-func)  ; Convert lambda to executable closure
                                      actual-func)))        ; Use symbol as-is
                                 ;; Handle direct lambda
                                 ((and (listp mutation-func) (eq (car mutation-func) 'lambda))
                                  (eval mutation-func))     ; Convert lambda to executable closure
                                 ;; Handle symbol
                                 (t mutation-func)))        ; Use symbol as-is
               (original-func-form mutation-func))          ; Preserve original form for test code
          (dotimes (i num-positions)
            (let* ((start-pos (cpo-tesmut-generator--random-position test-text))
                   (set-mark (< (/ (float (random 100)) 100) set-mark-prob))
                   (result (cpo-tesmut-generator--capture-mutation test-text start-pos executable-func set-mark transient-mark-mode-setting))
                   (success (nth 2 result)))

              (when (and success  ; Only generate test if mutation succeeded
                         (not (string= (nth 0 result) (nth 1 result))))  ; Buffer changed
                (let* ((before-text (nth 0 result))
                       (after-text (nth 1 result))
                       (func-name (cpo-tesmut-generator--function-name original-func-form))
                       (random-suffix (cpo-tesmut-generator--random-string 6))
                       (test-name (intern (format "%s-%s__%s" test-prefix func-name random-suffix)))
                       (test-code (cpo-tesmut-generator--create-cpo-tesmut-test
                                   before-text after-text executable-func test-name original-func-form transient-mark-mode-setting setup)))
                  (push test-code generated-tests)
                  (setq test-count (1+ test-count))))))))))

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
                  " --- Generated cpo-tesmut tests -*- lexical-binding: t; -*-\n\n")
          (insert ";; To run these tests from the command line:\n")
          (insert ";; emacs -batch -l ert -l cpo-tesmut.el -l "
                  (file-name-nondirectory output-file)
                  " -f ert-run-tests-batch-and-exit\n\n")
          (insert "(require 'cpo-tesmut)\n\n")
          (insert ";; Generated " (number-to-string test-count) " tests\n\n")

          ;; Insert tests in reverse order so they appear in the original order
          (dolist (test (reverse generated-tests))
            (insert test "\n\n"))))

      (message "Generated %d tests in %s (total: %d)" test-count output-file total-test-count)
      test-count)))

(defmacro cpo-tesmut-generate-tests (test-text num-positions mutation-functions output-file test-prefix
                                           &rest args)
  "Generate random tesmut tests and write them to OUTPUT-FILE.

This is a macro wrapper around `cpo-tesmut--generate-tests' that properly handles
default values for optional arguments.

TEST-TEXT: Multi-line string to test mutation functions on
NUM-POSITIONS: Number of random starting positions to try for each function
MUTATION-FUNCTIONS: List of mutation functions to test. Each element can be:
  - A symbol (e.g. 'insert)
  - A lambda form (e.g. '(lambda () (insert \"X\")))
  - A list of (name function) for better closure naming (e.g. '(\"insert-X\" (lambda () (insert \"X\"))))
  - A list of functions for multi-step sequence tests
OUTPUT-FILE: File to write generated tests to
TEST-PREFIX: Prefix for generated test names

Keyword arguments:
:set-mark-prob PROB - Probability (0.0-1.0) of setting mark before mutation (default 0.3)
:transient-mark-mode-prob PROB - Probability (0.0-1.0) that transient-mark-mode is enabled (default 1.0)
:generate-sequences BOOL - Generate sequence tests for lists of functions (default t)
:setup FORM - Setup code to include in generated tests (default nil)"
  (let ((set-mark-prob 0.3)
        (transient-mark-mode-prob 1.0)
        (generate-sequences t)
        (setup nil)
        (remaining-args args))

    ;; Parse keyword arguments
    (while remaining-args
      (pcase (pop remaining-args)
        (:set-mark-prob (setq set-mark-prob (pop remaining-args)))
        (:transient-mark-mode-prob (setq transient-mark-mode-prob (pop remaining-args)))
        (:generate-sequences (setq generate-sequences (pop remaining-args)))
        (:setup (setq setup (pop remaining-args)))
        (other (error "Unknown keyword argument: %s" other))))

    ;; Determine transient-mark-mode value based on probability
    (let ((transient-mark-mode-val (if (< (random 100) (* transient-mark-mode-prob 100)) t nil)))
      `(cpo-tesmut--generate-tests ,test-text ,num-positions ,mutation-functions ,output-file ,test-prefix
                               ,set-mark-prob ,transient-mark-mode-val ,generate-sequences ,setup))))

(defun tesmut-generate-simple-tests ()
  "Generate some simple example test files for demonstration."
  (interactive)

  ;; Test 1: Basic insertion and deletion
  (cpo-tesmut-generate-tests
   "The quick brown fox jumps over the lazy dog"
   10
   (list '("insert-X" (lambda () (insert "X")))
         '("insert-ABC" (lambda () (insert "ABC")))
         'delete-char
         'backward-delete-char)
   "__testing_cpo_tesmut_generator_1.el"
   "test-basic")

  ;; Test 2: Word operations with multiline text
  (cpo-tesmut-generate-tests
   "First line of text\nSecond line here\nThird line with more words\nFourth and final line"
   8
   (list 'kill-word
         'backward-kill-word
         '("kill-2-words" (lambda () (kill-word 2))))
   "__testing_cpo_tesmut_generator_2.el"
   "test-words")

  ;; Test 3: Region operations (higher mark probability)
  (cpo-tesmut-generate-tests
   "Start of buffer\nMiddle content with UPPERCASE\nEnd of buffer"
   5
   (list 'kill-region
         'upcase-region
         'downcase-region)
   "__testing_cpo_tesmut_generator_3.el"
   "test-region"
   :set-mark-prob 0.8) ; 80% chance of setting mark

  ;; Test 4: Sequence tests with mixed mutations
  (cpo-tesmut-generate-tests
   "Hello world! This is a test string."
   12
   (list 'kill-word
         '("insert-X" (lambda () (insert "X")))
         ;; Multi-step sequence test
         (list '("insert-A" (lambda () (insert "A")))
               'delete-char
               '("insert-B" (lambda () (insert "B")))))
   "__testing_cpo_tesmut_generator_4.el"
   "test-sequences"
   :set-mark-prob 0.5)

  ;; Test 5: Yank operations (requires kill-ring setup)
  (cpo-tesmut-generate-tests
   "One two three four five six seven eight nine ten"
   8
   (list 'kill-word
         '("yank-after-kill" (lambda () (kill-word 1) (forward-word 1) (yank)))
         '("kill-and-yank-twice" (lambda () (kill-word 1) (yank) (yank))))
   "__testing_cpo_tesmut_generator_5.el"
   "test-yank"))

(defmacro cpo-tesmut-generate-tests-batch (functions output-file base-test-prefix &rest test-inputs)
  "Generate multiple test suites using the same function list but different test inputs.
All tests will be written to the same output file, with subsequent calls appending to the file.

FUNCTIONS: List of mutation functions to test
OUTPUT-FILE: File to write all generated tests to (tests will be appended if file exists)
BASE-TEST-PREFIX: Base prefix for test names (will be suffixed with input suffix or index)
TEST-INPUTS: List of test input specifications. Each element should be a plist with:
  :text STRING - The test text
  :positions NUM - Number of test positions
  :suffix STRING - Suffix for test name (optional)
  :set-mark-prob PROB - Probability of setting mark (optional, default 0.3)
  :transient-mark-mode-prob PROB - Probability of transient-mark-mode (optional, default 0.8)
  :generate-sequences BOOL - Generate sequence tests (optional, default t)
  :setup FORM - Setup code (optional)

Example usage:
  (cpo-tesmut-generate-tests-batch
   '(kill-word delete-char)
   \"my-tests.el\"
   \"test-mutations\"
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
             (generate-sequences (if (plist-member input :generate-sequences)
                                   (plist-get input :generate-sequences)
                                 t))
             (setup (plist-get input :setup))
             (test-name (if suffix
                           (format "%s-%s" base-test-prefix suffix)
                         (format "%s-%d" base-test-prefix test-count))))

        (when (and text positions)
          (push `(cpo-tesmut-generate-tests
                  ,text
                  ,positions
                  (quote ,functions)
                  ,output-file
                  ,test-name
                  :set-mark-prob ,set-mark-prob
                  :transient-mark-mode-prob ,transient-mark-mode-prob
                  :generate-sequences ,generate-sequences
                  ,@(when setup `(:setup ,setup)))
                all-tests)
          (setq test-count (1+ test-count)))))

    ;; Return a progn form with all the test generation calls
    `(progn ,@(reverse all-tests))))

(provide 'cpo-tesmut-generator)
