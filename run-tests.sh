#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GENERATED_DIR="$SCRIPT_DIR/examples/generated-example-tests"

usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Run the emacs-caretest test suite.

Options:
  --core        Run the framework unit tests.
  --generators  Run the example generators and test the generated output.
  --all         Run generators and all tests (--generators + --core).
  --clean       Delete the examples/generated-example-tests directory and exit.
  --help        Show this message and exit.
EOF
}

if [ $# -eq 0 ]; then
    usage
    exit 0
fi

CLEAN=false
RUN_CORE=false
RUN_GENERATORS=false

for arg in "$@"; do
    case "$arg" in
        --help)
            usage
            exit 0
            ;;
        --clean)
            CLEAN=true
            ;;
        --core)
            RUN_CORE=true
            ;;
        --generators)
            RUN_GENERATORS=true
            ;;
        --all)
            RUN_CORE=true
            RUN_GENERATORS=true
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

if $RUN_GENERATORS; then
    # Remove stale generated files so generators start fresh each run
    if [ -d "$GENERATED_DIR" ]; then
        rm -f "$GENERATED_DIR"/*.el
    fi

    # Run example generators (they create examples/generated-example-tests/ if needed)
    emacs -batch \
        -l carettest-tesmo.el \
        -l carettest-tesmo-generator.el \
        -l examples/example-tesmo-generator.el

    emacs -batch \
        -l carettest-tesmut.el \
        -l carettest-tesmut-generator.el \
        -l examples/example-tesmut-generator.el
fi

# Build test load args and run all selected tests in a single emacs invocation
TEST_ARGS=(-l ert -l carettest-tesmo.el -l carettest-tesmut.el -l carettest-tesprop.el)

if $RUN_CORE; then
    TEST_ARGS+=(-l test-carettest-tesmo.el -l test-carettest-tesmut.el -l test-carettest-tesprop.el)
fi

if $RUN_GENERATORS; then
    for f in "$GENERATED_DIR"/*.el; do
        [ -f "$f" ] && TEST_ARGS+=(-l "$f")
    done
fi

emacs -batch "${TEST_ARGS[@]}" -f ert-run-tests-batch-and-exit
