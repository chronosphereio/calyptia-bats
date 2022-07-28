#!/usr/bin/env bash
set -eo pipefail

# Verifies if all the given variables are set, and exits otherwise
# Parameters:
# Variadic: variable names to check presence of
function ensure_variables_set() {
    missing=""
    for var in "$@"; do
        if [ -z "${!var}" ]; then
            missing+="$var "
        fi
    done
    if [ -n "$missing" ]; then
        if [[ $(type -t fail) == function ]]; then
            fail "Missing required variables: $missing"
        else
            echo "Missing required variables: $missing" >&2
            exit 1
        fi
    fi
}

# Finds a random, unused port on the system and echos it.
# Returns 1 and echos -1 if it can't find one.
# Have to do it this way to prevent variable shadowing.
function find_unused_port() {
    local portnum
    while true; do
        portnum=$(shuf -i 1025-65535 -n 1)
        if ! lsof -Pi ":$portnum" -sTCP:LISTEN; then
            echo "$portnum"
            return 0
        fi
    done
    echo -1
    return 1
}

# Waits for the given cURL call to succeed.
# Parameters:
# $1: the number of attempts to try loading before failing
# Remaining parameters: passed directly to cURL.
function wait_for_curl() {
    local MAX_ATTEMPTS=$1
    shift
    local ATTEMPTS=0

    # This function may be run outside of BATS, so ensure `fail` has a definition
    if [[ $(type -t fail) != function ]]; then
        function fail() {
            local message=$1
            echo "FAIL: $message"
            exit 1
        }
    fi

    if [ "${VERBOSITY:-0}" -gt 1 ]; then
        echo "Curl command: curl -s -o /dev/null -f $*"
    fi
    until curl -s -o /dev/null -f "$@"; do
        # Prevent an infinite loop - at 2 seconds per go this is 10 minutes
        if [ $ATTEMPTS -gt "300" ]; then
            fail "wait_for_curl ultimate max exceeded: $*"
        fi
        if [ $ATTEMPTS -gt "$MAX_ATTEMPTS" ]; then
            fail "unable to perform cURL: $*"
        fi
        ATTEMPTS=$((ATTEMPTS+1))
        sleep 2
    done
}

function wait_for_container_status() {
    local MAX_ATTEMPTS=$1
    local CONTAINER_NAME=$2
    local CONTAINER_STATUS=${3:-running}

    shift
    local ATTEMPTS=0

    # This function may be run outside of BATS, so ensure `fail` has a definition
    if [[ $(type -t fail) != function ]]; then
        function fail() {
            local message=$1
            echo "FAIL: $message"
            exit 1
        }
    fi

    until [ "$("$CONTAINER_RUNTIME" ps -q -f status="${CONTAINER_STATUS}" -f name=^/"${CONTAINER_NAME}"$)" ]; do
        # Prevent an infinite loop - at 2 seconds per go this is 10 minutes
        if [ $ATTEMPTS -gt "300" ]; then
            fail "wait_for_container_status ultimate max exceeded: $*"
        fi
        if [ $ATTEMPTS -gt "$MAX_ATTEMPTS" ]; then
            fail "wait_for_container_status unable to find output: $*"
        fi
        ATTEMPTS=$((ATTEMPTS+1))
        sleep 5
    done
}

# Waits for the given URL to return 200
# Parameters:
# $1: the number of attempts to try loading before failing
# $2: the URL to load
# $3: HTTP basic authentication credentials (format: username:password) [optional]
function wait_for_url() {
    local MAX_ATTEMPTS=$1
    local URL=$2
    local CREDENTIALS=${3-}
    local extra_args=""
    if [ -n "$CREDENTIALS" ]; then
        extra_args="-u $CREDENTIALS"
    fi
    # shellcheck disable=SC2086
    wait_for_curl "$MAX_ATTEMPTS" "$URL" $extra_args
}

function wait_for_container_output() {
    local MAX_ATTEMPTS=$1
    local CONTAINER_NAME=$2
    local EXPECTED_OUTPUT=$3

    shift
    local ATTEMPTS=0

    # This function may be run outside of BATS, so ensure `fail` has a definition
    if [[ $(type -t fail) != function ]]; then
        function fail() {
            local message=$1
            echo "FAIL: $message"
            exit 1
        }
    fi

    if ! "$CONTAINER_RUNTIME" logs "$CONTAINER_NAME" ; then
        fail "unable to get logs for container: $CONTAINER_NAME"
    fi

    until "$CONTAINER_RUNTIME" logs "$CONTAINER_NAME"|grep -qF "$EXPECTED_OUTPUT" ; do
        # Prevent an infinite loop - at 5 seconds per go this is 10 minutes
        if [ $ATTEMPTS -gt "120" ]; then
            fail "wait_for_container_output ultimate max exceeded: \"$EXPECTED_OUTPUT\" ($*)"
        fi
        if [ $ATTEMPTS -gt "$MAX_ATTEMPTS" ]; then
            fail "wait_for_container_output unable to find output: \"$EXPECTED_OUTPUT\" ($*)"
        fi
        ATTEMPTS=$((ATTEMPTS+1))
        sleep 5
    done
}

function check_remote_file_exists() {
    if [[ $(curl -o /dev/null --silent --head --write-out '%{http_code}' "$1") != "200" ]]; then
        fail "remote file does not exist: $1"
    fi
}

# this function is used to create a unique string used to uniquely identify messages.
function random_string() {
	local chars=abcdefghijklmnopqrstuvwxyz0123456890
	# shellcheck disable=SC2034
	for i in {1..32} ; do
		echo -n "${chars:RANDOM%${#chars}:1}" | sha256sum | cut -f1 -d' '
	done
	echo
}
