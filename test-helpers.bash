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

    # Note for failing containers, logs go to stderr
    until ("$CONTAINER_RUNTIME" logs "$CONTAINER_NAME" || :) 2>&1 | grep -qF "$EXPECTED_OUTPUT" ; do
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

function wait_for_container_output_matching_file() {
    local MAX_WAIT_SECONDS=$1
    local CONTAINER_NAME=$2
    local EXPECTED_OUTPUT_FILE=$3
    local POLL_INTERVAL=${4:-1}

    local MAX_POSSIBLE_WAIT_SECONDS=600  # never run for more than 10 minutes
    local MAX_ATTEMPTS=$((MAX_WAIT_SECONDS / POLL_INTERVAL))
    local MAX_POSSIBLE_ATTEMPTS=$((MAX_POSSIBLE_WAIT_SECONDS / POLL_INTERVAL))

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

    # Pipe both "docker logs" and expected_output through tr replacing newlines with non-printable byte. This
    # allows grep to match a multline string against docker logs output
    # Note for failing containers, logs go to stderr
    until ("$CONTAINER_RUNTIME" logs "$CONTAINER_NAME" || :) 2>&1 | tr '\n' '\1' | grep -qF "$(tr '\n' '\1' < $EXPECTED_OUTPUT_FILE)" ; do
        if [ $ATTEMPTS -gt "$MAX_POSSIBLE_ATTEMPTS" ]; then
            fail "wait_for_container_output_matching_file ultimate max exceeded: \"$(cat $EXPECTED_OUTPUT_FILE)\" ($*)"
        fi
        if [ $ATTEMPTS -gt "$MAX_ATTEMPTS" ]; then
            fail "wait_for_container_output_matching_file unable to find output: \"$(cat $EXPECTED_OUTPUT_FILE)\" ($*)"
        fi
        ATTEMPTS=$((ATTEMPTS+1))
        sleep $POLL_INTERVAL
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

# Function to check the reload count provided by Fluent Bit matches a value:
# https://docs.fluentbit.io/manual/administration/hot-reload
# Typically used to trigger a reload and then wait for it to happen.
function wait_for_reload_count() {
    local calyptia_host=${1:?}
    local reload_count=${2:?}
    local max_attempts=${3:-10}

    wait_for_url "$max_attempts" "$calyptia_host/api/v2/reload"

    local attempts=0
    # This function may be run outside of BATS, so ensure `fail` has a definition
    if [[ $(type -t fail) != function ]]; then
        function fail() {
            local message=$1
            echo "FAIL: $message"
            exit 1
        }
    fi

    local current_reload_count
    current_reload_count="$(curl -sSf -X GET "$calyptia_host/api/v2/reload" | jq -cr '.hot_reload_count')"

    until [[ "$current_reload_count" == "$reload_count" ]]; do
        # Prevent an infinite loop - at 2 seconds per go this is 10 minutes
        if [ $attempts -gt "300" ]; then
            fail "wait_for_reload_count ultimate max exceeded: $current_reload_count != $reload_count"
        fi
        if [ $attempts -gt "$max_attempts" ]; then
            fail "wait_for_reload_count unable to match value: $current_reload_count != $reload_count"
        fi
        attempts=$((attempts+1))
        sleep 5
        current_reload_count="$(curl -X GET "$calyptia_host/api/v2/reload" | jq -cr '.hot_reload_count')"
    done
}
