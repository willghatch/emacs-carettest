#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GENERATED_DIR="$SCRIPT_DIR/examples/generated-example-tests"

usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Run the emacs-caretest test suite.

Options:
  --clean   Delete the examples/generated-example-tests directory and exit.
  --help    Show this message and exit.

Without options, the script:
  1. Runs the example generators to populate examples/generated-example-tests/.
  2. Runs the generated example tests.
  3. Runs the framework unit tests.
EOF
}

CLEAN=false

for arg in "$@"; do
    case "$arg" in
        --help)
            usage
            exit 0
            ;;
        --clean)
            CLEAN=true
            ;;
        *)
            echo "Unknown option: $arg" >&2
            usage >&2
            exit 1
            ;;
    esac
done

if $CLEAN; then
    if [ -d "$GENERATED_DIR" ]; then
        rm -rf "$GENERATED_DIR"
        echo "Deleted $GENERATED_DIR"
    else
        echo "Nothing to clean: $GENERATED_DIR does not exist."
    fi
    exit 0
fi

cd "$SCRIPT_DIR"

# Remove stale generated files so generators start fresh each run
rm -f "$GENERATED_DIR/generated-tesmo-example.el"
rm -f "$GENERATED_DIR/generated-tesmut-example.el"

# Run example generators (they create examples/generated-example-tests/ if needed)
emacs -batch \
    -l cpo-tesmo.el \
    -l cpo-tesmo-generator.el \
    -l examples/example-tesmo-generator.el

emacs -batch \
    -l cpo-tesmut.el \
    -l cpo-tesmut-generator.el \
    -l examples/example-tesmut-generator.el

# Run generated example tests
emacs -batch \
    -l ert \
    -l cpo-tesmo.el \
    -l "$GENERATED_DIR/generated-tesmo-example.el" \
    -f ert-run-tests-batch-and-exit

emacs -batch \
    -l ert \
    -l cpo-tesmut.el \
    -l "$GENERATED_DIR/generated-tesmut-example.el" \
    -f ert-run-tests-batch-and-exit

# Run framework unit tests
emacs -batch -l ert -l cpo-tesmo.el -l test-cpo-tesmo.el -f ert-run-tests-batch-and-exit
emacs -batch -l ert -l cpo-tesmut.el -l test-cpo-tesmut.el -f ert-run-tests-batch-and-exit
