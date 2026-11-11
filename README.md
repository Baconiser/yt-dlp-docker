# yt-dlp Docker image — always the latest version

A Docker image that always runs the **latest stable yt-dlp**, kept fresh by two layers:

1. **Baked at build time** — the Dockerfile installs whatever the current latest stable is from PyPI (`pip install "yt-dlp[default]"`, unpinned).
2. **Refreshed at runtime** — `entrypoint.sh` compares the installed version against PyPI on *every container start* and upgrades before running your command. When the baked version is already current, the check is a single fast HTTP call and pip is skipped entirely.
3. *(Optional)* **Rebuilt daily by GitHub Actions** — the included workflow publishes `ghcr.io/<OWNER>/<REPO>/yt-dlp:latest` (plus a `:<version>` tag) so you can pull a fresh image without building anything.

## Files

```
yt-dlp-docker/
├── Dockerfile                       # python:3.13-slim + ffmpeg + yt-dlp[default]
├── entrypoint.sh                    # runtime auto-update + command dispatch
├── .dockerignore
├── docker-compose.yml               # compose example
├── yt-dlp-docker                    # host wrapper: use the image like a native CLI
└── .github/workflows/docker.yml     # daily build & push to GHCR
```

## Quick start (local build)

```sh
docker build -t yt-dlp:latest .

# download into the current folder (mounted at /downloads, which is the WORKDIR)
docker run --rm -v "$PWD:/downloads" yt-dlp:latest "https://www.youtube.com/watch?v=BaW_jenozKc"

# explicit quality preset + thumbnail/metadata embedding (ffmpeg is baked in)
docker run --rm -v "$PWD:/downloads" yt-dlp:latest \
    -f "bv*+ba/b" --merge-output-format mp4 --embed-thumbnail --embed-metadata \
    "https://www.youtube.com/watch?v=BaW_jenozKc"
```

There is **no baked-in yt-dlp config** — every flag is passed by you; the image only sets the working directory to `/downloads`.

## Passing arguments and commands

The entrypoint dispatches on the first argument:

```sh
# plain args -> forwarded to yt-dlp (args starting with "-" always go to yt-dlp)
docker run --rm -v "$PWD:/downloads" yt-dlp:latest --version

# first arg that is a real executable is run directly:
docker run --rm -v "$PWD:/downloads" yt-dlp:latest yt-dlp --version
docker run --rm -it -v "$PWD:/downloads" yt-dlp:latest bash      # shell into the image
docker run --rm -v "$PWD:/downloads" yt-dlp:latest python -c "print('hi')"
```

## Convenience wrapper (feels like a native binary)

```sh
cp yt-dlp-docker ~/.local/bin/ && chmod +x ~/.local/bin/yt-dlp-docker

yt-dlp-docker "https://www.youtube.com/watch?v=BaW_jenozKc"
yt-dlp-docker -f "bv*+ba/b" <URL>
yt-dlp-docker bash            # arbitrary commands work too
```

The wrapper mounts your current directory, runs as **your own UID/GID** (no root-owned output files) and still auto-updates, because non-root upgrades install into the writable `/opt/pyuser` location inside the image.

## docker compose

```sh
docker compose build
docker compose run --rm yt-dlp <URL>
```

To use the CI-published image instead of a local build, comment `build:` and set `image: ghcr.io/<OWNER>/<REPO>/yt-dlp:latest`.

## Keeping it always-latest via GitHub Actions (GHCR)

1. Push this folder to a GitHub repository **keeping the `.github/` directory**.
2. The workflow (`.github/workflows/docker.yml`) runs on pushes to `main`, manually, and **daily at 05:23 UTC**. It resolves the latest stable version from PyPI and — if a `:<version>` tag isn't published yet — builds and pushes:
   - `ghcr.io/<owner>/<repo>/yt-dlp:latest`
   - `ghcr.io/<owner>/<repo>/yt-dlp:<yt-dlp-version>`
3. Packages are **private by default** — make it public under your repo's *Packages* settings, or `docker login ghcr.io` before pulling.
4. Pull and run:

```sh
docker pull ghcr.io/<OWNER>/<REPO>/yt-dlp:latest
docker run --rm -v "$PWD:/downloads" ghcr.io/<OWNER>/<REPO>/yt-dlp:latest <URL>
```

## Configuration (environment variables)

| Variable        | Default  | Meaning                                                                                     |
|-----------------|----------|---------------------------------------------------------------------------------------------|
| `AUTOUPDATE`    | `1`      | `1` = check PyPI and upgrade on every start; `0` = run the baked version as-is              |
| `YTDLP_CHANNEL` | `stable` | `stable` (latest tagged release) / `nightly` (pip `--pre`, recommended by the yt-dlp README) / `master` (git tarball) |

Example: fastest possible start, no update check:

```sh
docker run --rm -e AUTOUPDATE=0 -v "$PWD:/downloads" yt-dlp:latest <URL>
```

## What's inside

- **`python:3.13-slim`** (Debian) base, amd64.
- **ffmpeg** from apt — required for merging `bv*+ba` streams and for embedding thumbnails/metadata.
- **`yt-dlp[default]`** pip extras — brotli, certifi, mutagen, pycryptodomex, requests/urllib3, websockets; also pulls **yt-dlp-ejs** (yt-dlp's YouTube JS-challenge engine).
- No JavaScript runtime — for some YouTube scenarios yt-dlp wants one (deno or node). If you ever need it, add `nodejs` to the `apt-get install` line in the Dockerfile.

## Notes & troubleshooting

- **Update check fails (offline/behind proxy)?** The entrypoint warns and keeps the baked version — the run still proceeds. Use `AUTOUPDATE=0` to silence it.
- **Nightly/master channels** always run a pip resolve at start (no cheap version gate), so startup takes ~10–20 s longer than stable when already current.
- **Root vs. non-root:** as root, runtime upgrades go to `/usr/local`; as any other user they go to `/opt/pyuser` (world-writable). Either way `yt-dlp` resolves to the newest build via `PATH`.
- **yt-dlp self-update:** `yt-dlp -U` inside this container is *not* the update mechanism (pip installs can't self-update); the entrypoint's pip upgrade is. `--update-to nightly` still works if you want to switch channels for a single run.
