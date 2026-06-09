#!/bin/bash
USER_HOME="${HOME}"
if [ -n "$SUDO_USER" ]; then
    USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
fi
export LD_LIBRARY_PATH="$USER_HOME/local/lib"
cd "$USER_HOME/repos/split" || exit 1
exec "$USER_HOME/repos/split/build/apps/DEPO/DEPO" --gss --edp --gpu 0 "$@" 2>&1
