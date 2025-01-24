#!/bin/bash

# Get the name of the calling program
PROGRAM_NAME="$(basename "${0}")"

logdate() {
    date "+%Y-%m-%d %H:%M:%S"
}

log() {
    local level="${1}"
    shift
    echo >&2 "[$(logdate)] [${PROGRAM_NAME}] [${level}] ${*}"
}

info() {
    log "INFO" "${@}"
}

warning() {
    log "WARNING" "${@}"
}

error() {
    log "ERROR" "${@}"
}

fatal() {
    error "${@}"
    exit 1
} 