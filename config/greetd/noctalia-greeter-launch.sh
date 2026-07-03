#!/usr/bin/env bash
# greetd launcher for noctalia-greeter with correct config path
export NOCTALIA_GREETER_STATE_DIR=/var/lib/greeter/noctalia-greeter
exec /usr/bin/noctalia-greeter-session
