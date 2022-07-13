#!/bin/bash
set -eo pipefail

# The root of the tests to run locally, i.e. the custom test files we want to execute.
export TEST_ROOT=${TEST_ROOT:?}

# The branch to use in the Calyptia BATS repository
export CALYTPIA_BATS_REF=${CALYTPIA_BATS_REF:-main}
# THe local directory to check out Calyptia BATS into, if this exists we will do nothing for Calyptia BATS
export CALYPTIA_BATS_DIR=${CALYPTIA_BATS_DIR:-$PWD/calyptia-bats}

# Helper files can include custom functions to simplify testing
export HELPERS_ROOT=${HELPERS_ROOT:-$CALYPTIA_BATS_DIR}
# Any -helpers.bash files in this directory will be source'd to add custom helper functions per test root
export CUSTOM_HELPERS_ROOT=${CUSTOM_HELPERS_ROOT:-$TEST_ROOT/helpers/}

# Some common options
export CONTAINER_RUNTIME=${CONTAINER_RUNTIME:-docker}
export BATS_FORMATTER=${BATS_FORMATTER:-tap}
export BATS_ARGS=${BATS_ARGS:---timing --verbose-run}

# BATS installation location
export BATS_ROOT=${BATS_ROOT:-$CALYPTIA_BATS_DIR/bats}
export BATS_FILE_ROOT=$BATS_ROOT/lib/bats-file
export BATS_SUPPORT_ROOT=$BATS_ROOT/lib/bats-support
export BATS_ASSERT_ROOT=$BATS_ROOT/lib/bats-assert
export BATS_DETIK_ROOT=$BATS_ROOT/lib/bats-detik

# BATS support tool versions
export BATS_ASSERT_VERSION=${BATS_ASSERT_VERSION:-2.0.0}
export BATS_SUPPORT_VERSION=${BATS_SUPPORT_VERSION:-0.3.0}
export BATS_FILE_VERSION=${BATS_FILE_VERSION:-0.3.0}
export BATS_DETIK_VERSION=${BATS_DETIK_VERSION:-1.0.0}

function install_calyptia_bats() {
    if [[ -d "$CALYPTIA_BATS_DIR" ]]; then
        echo "Found existing CALYPTIA_BATS_DIR directory so assuming already present."
    else
        git clone -b "$CALYTPIA_BATS_REF" https://github.com/calyptia/bats.git "$CALYPTIA_BATS_DIR"
    fi
}

function install_bats() {
    echo "Reinstalling BATS support libraries to $BATS_ROOT"
    rm -rf  "${BATS_ROOT}"
    mkdir -p "${BATS_ROOT}/lib"
    DOWNLOAD_TEMP_DIR=$(mktemp -d)

    # Install BATS helpers using specified versions
    pushd "${DOWNLOAD_TEMP_DIR}"
        curl -sLO "https://github.com/bats-core/bats-assert/archive/refs/tags/v$BATS_ASSERT_VERSION.zip"
        unzip -q "v$BATS_ASSERT_VERSION.zip"
        mv -f "${DOWNLOAD_TEMP_DIR}/bats-assert-$BATS_ASSERT_VERSION" "${BATS_ASSERT_ROOT}"
        rm -f "v$BATS_ASSERT_VERSION.zip"

        curl -sLO "https://github.com/bats-core/bats-support/archive/refs/tags/v$BATS_SUPPORT_VERSION.zip"
        unzip -q "v$BATS_SUPPORT_VERSION.zip"
        mv -f "${DOWNLOAD_TEMP_DIR}/bats-support-$BATS_SUPPORT_VERSION" "${BATS_SUPPORT_ROOT}"
        rm -f "v$BATS_SUPPORT_VERSION.zip"

        curl -sLO "https://github.com/bats-core/bats-file/archive/refs/tags/v$BATS_FILE_VERSION.zip"
        unzip -q "v$BATS_FILE_VERSION.zip"
        mv -f "${DOWNLOAD_TEMP_DIR}/bats-file-$BATS_FILE_VERSION" "${BATS_FILE_ROOT}"
        rm -f "v$BATS_FILE_VERSION.zip"

        curl -sLO "https://github.com/bats-core/bats-detik/archive/refs/tags/v$BATS_DETIK_VERSION.zip"
        unzip -q "v$BATS_DETIK_VERSION.zip"
        mv -f "${DOWNLOAD_TEMP_DIR}/bats-detik-$BATS_DETIK_VERSION/lib" "${BATS_DETIK_ROOT}"
        rm -f "v$BATS_DETIK_VERSION.zip"
    popd
    rm -rf "${DOWNLOAD_TEMP_DIR}"
}

# Helper function to run a set of tests based on our specific configuration
# This function will call `exit`, so any cleanup must be done inside of it.
function run_tests() {
    local requested=$1
    local run=""

    if [[ "$requested" == "all" ]] || [ -z "$requested" ]; then
        # Empty => everything. Alternatively, explicitly ask for it.
        # When running advanced we also need to run standard
        run="--recursive ${TEST_ROOT}/"
    elif [[ "$requested" =~ .*\.bats$ ]]; then
        # One individual test
        run="$requested"
    elif [ -d "${TEST_ROOT}/$requested" ]; then
        # Likely an individual integration suite
        run="--recursive ${TEST_ROOT}/$requested"
    fi

    echo
    echo
    echo "========================"
    echo "Starting tests."
    echo "========================"
    echo
    echo

    # We run BATS in a subshell to prevent it from inheriting our exit/err trap, which can mess up its internals
    # We set +exu because unbound variables can cause test failures with zero context
    set +xeu
    # shellcheck disable=SC2086
    (bats --formatter "${BATS_FORMATTER}" $run $BATS_ARGS)
    local bats_retval=$?

    echo
    echo
    echo "========================"
    if [ "$bats_retval" -eq 0 ]; then
        echo "All tests passed!"
    else
        echo "Some tests failed. Please inspect the output above for details."
    fi
    echo "========================"
    echo
    echo
    exit $bats_retval
}

if [[ "${SKIP_BATS_INSTALL:-no}" != "yes" ]]; then
    install_calyptia_bats
    install_bats
fi

# shellcheck disable=SC1091
source "$HELPERS_ROOT/test-helpers.bash"

# Now source any additional `-helpers.bash` files we fine in CUSTOM_HELPERS_ROOT
if [[ -d "$CUSTOM_HELPERS_ROOT" ]]; then
    for CUSTOM_HELPER_FILE in "$CUSTOM_HELPERS_ROOT"/*-helpers.bash
    do
        # shellcheck source=/dev/null
        source "$CUSTOM_HELPER_FILE"
    done
fi
run_tests "$@"