# syntax=docker/dockerfile:1
#
# yt-dlp Docker image that always runs the latest stable release.
# Layer 1: bakes the current latest stable from PyPI at build time.
# Layer 2: entrypoint.sh re-checks PyPI on every container start and
#          upgrades before exec'ing your command, so runs are always current.

FROM python:3.13-slim

LABEL org.opencontainers.image.title="yt-dlp (always latest)" \
      org.opencontainers.image.description="Latest stable yt-dlp + ffmpeg; self-updates on every container start" \
      org.opencontainers.image.licenses="Unlicense"

ENV PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_ROOT_USER_ACTION=ignore \
    PYTHONUNBUFFERED=1 \
    PYTHONUSERBASE=/opt/pyuser \
    AUTOUPDATE=1 \
    YTDLP_CHANNEL=stable \
    HOME=/config

# ffmpeg: merging separate video/audio streams + post-processing (metadata, thumbnails)
RUN apt-get update \
    && apt-get install -y --no-install-recommends ffmpeg \
    && rm -rf /var/lib/apt/lists/*

# Deno: JS runtime that yt-dlp uses (via yt-dlp-ejs) to solve YouTube's JS
# challenges. Installed as a static binary straight from the latest release,
# using the base image's Python, so no extra apt packages are pulled in.
RUN python - <<'EOF'
import io, os, platform, urllib.request, zipfile
arch = {"x86_64": "x86_64", "aarch64": "aarch64"}[platform.machine()]
url = f"https://github.com/denoland/deno/releases/latest/download/deno-{arch}-unknown-linux-gnu.zip"
with urllib.request.urlopen(url) as r, zipfile.ZipFile(io.BytesIO(r.read())) as z:
    z.extract("deno", "/usr/local/bin")
os.chmod("/usr/local/bin/deno", 0o755)
EOF
RUN deno --version

# Bake the current latest stable so the image is usable offline;
# "yt-dlp[default]" adds brotli, certifi, mutagen, pycryptodomex,
# requests/urllib3, websockets (and pulls yt-dlp-ejs for YouTube).
RUN python -m pip install --no-cache-dir --upgrade "yt-dlp[default]"

# Writable dirs so the image also works with `docker run --user $(id -u):$(id -g)`:
#   /downloads  default working/download dir (mount your folder here)
#   /config     HOME for caches (cookies etc.)
#   /opt/pyuser pip "user scheme" target for runtime upgrades by non-root users
RUN mkdir -p /downloads /config /opt/pyuser/bin /opt/pyuser/lib/python3.13/site-packages \
    && chmod 777 /downloads /config \
    && chmod -R 777 /opt/pyuser

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod 0755 /usr/local/bin/entrypoint.sh

WORKDIR /downloads
VOLUME ["/downloads"]

# entrypoint.sh dispatches:
#   docker run IMG <args>          -> yt-dlp <args>
#   docker run IMG yt-dlp <args>   -> yt-dlp <args> (direct passthrough)
#   docker run IMG bash            -> arbitrary command / shell
ENTRYPOINT ["entrypoint.sh"]
CMD []
