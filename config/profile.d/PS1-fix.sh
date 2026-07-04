#!/bin/bash
# Workaround: ensure PS1 is set before any profile.d script runs
# This gets sourced early via /etc/profile

if [[ -z "${PS1:-}" ]]; then
    export PS1='\[\033[0;1m\][\u@\h \W]\$\[\033[0m\] '
fi
