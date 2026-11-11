#!/bin/sh
# Entrypoint: bring yt-dlp to the latest version, then exec the requested command.
#
# Env knobs:
#   AUTOUPDATE=1|0          (default 1) check for a newer yt-dlp on every start
#   YTDLP_CHANNEL=stable|nightly|master  (default stable)
#
# Dispatch:
#   - first arg is an executable (yt-dlp, bash, python, ...) -> exec it directly
#   - otherwise -> exec yt-dlp with all args
set -u

AUTOUPDATE="${AUTOUPDATE:-1}"
YTDLP_CHANNEL="${YTDLP_CHANNEL:-stable}"
PYUSERBASE="${PYTHONUSERBASE:-/opt/pyuser}"

# Non-root upgrades land here (see Dockerfile); put its scripts on PATH.
export PYTHONUSERBASE="$PYUSERBASE"
PATH="$PYUSERBASE/bin:$PATH"
export PATH

pypi_latest_version() {
    python -c 'import json, urllib.request; print(json.load(urllib.request.urlopen("https://pypi.org/pypi/yt-dlp/json", timeout=15))["info"]["version"])' 2>/dev/null || echo '?'
}

update_ytdlp() {
    case "$YTDLP_CHANNEL" in
        nightly)
            # README-recommended channel; always resolves via pip (no cheap version gate)
            python -m pip install -qU --pre "yt-dlp[default]"
            ;;
        master)
            python -m pip install -qU "yt-dlp[default] @ https://github.com/yt-dlp/yt-dlp/archive/master.tar.gz"
            ;;
        *)
            python -m pip install -qU "yt-dlp[default]"
            ;;
    esac
}

if [ "$AUTOUPDATE" = "1" ]; then
    current="$(yt-dlp --version 2>/dev/null || echo 'none')"

    if [ "$YTDLP_CHANNEL" = "stable" ]; then
        # Cheap check first: hit PyPI once and skip pip entirely when current.
        latest="$(pypi_latest_version)"
        if [ "$latest" != "$current" ]; then
            echo "[entrypoint] updating yt-dlp: $current -> $latest ..."
            update_ytdlp || echo "[entrypoint] WARN: update failed, keeping $current" >&2
        fi
    else
        update_ytdlp || echo "[entrypoint] WARN: update failed, keeping $(yt-dlp --version 2>/dev/null || echo "$current")" >&2
    fi
fi

# Pass-through: if the first argument is an executable on PATH (yt-dlp, bash,
# sh, python, ...), run it directly; args starting with "-" always go to yt-dlp.
if [ "$#" -gt 0 ] && [ "${1#-}" = "$1" ]; then
    if command -v "$1" >/dev/null 2>&1; then
        exec "$@"
    fi
fi

exec yt-dlp "$@"
