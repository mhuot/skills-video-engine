# Skills Video Engine

One portable production studio for agent video skills. This public OCI image
packages the shared generation toolchain used by
[explainer-video](https://github.com/mhuot/explainer-video-skill) and future
video skills such as promo-video:

- HyperFrames for deterministic HTML/CSS/JavaScript video rendering
- Kokoro-82M for local narration
- FFmpeg and FFprobe for encoding and media QA
- Python 3.12, Node.js 22, Chromium, and chrome-headless-shell

After the image is pulled, generation can run without network access. Project
files remain on the host and are mounted into `/project`.
The image also includes the pinned GSAP browser runtime, so project
scaffolding does not need to contact a CDN.

For a guided browser and MCP experience over this Engine, use
[`skills-video-studio`](https://github.com/mhuot/skills-video-studio). Studio
runs reviewed production recipes, captures command and job metadata, and can
incrementally rerender changed composition segments before rebuilding the
master without re-encoding unchanged video.

## See the engine in action

<p align="center">
  <a href="docs/assets/showcase/skills-video-engine-explainer.mp4?raw=1">
    <img src="docs/assets/showcase/storyboard-contact-sheet.jpg" alt="Storyboard for the Skills Video Engine explainer" width="900">
  </a>
</p>

<p align="center">
  <strong><a href="docs/assets/showcase/skills-video-engine-explainer.mp4?raw=1">Watch or download the 75-second explainer (MP4)</a></strong>
</p>

The engine puts narration, browser rendering, encoding, fonts, and media checks
in one versioned environment. Pull once, mount a project, and invoke each
production tool directly.

| One production toolchain | Native multi-architecture image | Verified publishing |
| --- | --- | --- |
| <img src="docs/assets/showcase/production-toolchain.webp" alt="Narration, browser rendering, encoding, fonts, and media checks shown as one toolchain" width="320"> | <img src="docs/assets/showcase/native-multi-arch.webp" alt="Docker selecting the native ARM64 Skills Video Engine image" width="320"> | <img src="docs/assets/showcase/publish-with-provenance.webp" alt="AMD64 and ARM64 builds passing smoke tests with SBOM and provenance" width="320"> |
| The same foundations for every video skill. | Linux AMD64 and ARM64, with native selection on Apple Silicon. | Smoke-tested images published with SBOM and provenance attestations. |

Explainer production files and methodology are available in the
[skills-video-engine-explainer source repository](https://github.com/mhuot/skills-video-engine-explainer).

## Pull

```bash
export SKILLS_VIDEO_ENGINE_IMAGE="${SKILLS_VIDEO_ENGINE_IMAGE:-ghcr.io/mhuot/skills-video-engine:0.3.1}"
docker pull "$SKILLS_VIDEO_ENGINE_IMAGE"
```

## Quick start with Docker Compose

For users who know basic Docker but do not want to repeat the full `docker
run` contract, clone this repository once and run the helper from any video
project:

```bash
git clone https://github.com/mhuot/skills-video-engine "$HOME/skills-video-engine"
cd /path/to/video-project
mkdir -p production/renders production/snapshots
"$HOME/skills-video-engine/scripts/engine.sh" --workdir video hyperframes lint
"$HOME/skills-video-engine/scripts/engine.sh" --workdir video hyperframes check
"$HOME/skills-video-engine/scripts/engine.sh" \
  --workdir video \
  hyperframes render --quality high --output ../production/renders/master.mp4
```

The helper mounts the current directory at `/project`, runs as your host
UID/GID, disables container networking, enables an init process, and gives
headless Chromium a 1 GiB shared-memory segment. Set `VIDEO_PROJECT_DIR` to
run against a different project:

```bash
VIDEO_PROJECT_DIR=/path/to/video-project \
  "$HOME/skills-video-engine/scripts/engine.sh" python tools/tts_generate.py
```

This works with projects created by
[`explainer-video-skill`](https://github.com/mhuot/explainer-video-skill) and
with ad hoc projects that provide their own scripts and `video/index.html`.
Commands are arguments passed directly to the container; the helper does not
evaluate project-supplied shell strings.

Production uses a released version or immutable digest, never `latest`.
Developers can override `SKILLS_VIDEO_ENGINE_IMAGE` with a local tag or digest.
Capture the resolved image in the production record:

```bash
docker image inspect "$SKILLS_VIDEO_ENGINE_IMAGE" \
  --format '{{if .RepoDigests}}{{index .RepoDigests 0}}{{else}}local:no-digest{{end}} {{.Id}}'
```

`local:no-digest` is suitable only for development.

## Verify the environment

```bash
docker version
docker run --rm "$SKILLS_VIDEO_ENGINE_IMAGE" hyperframes --version
docker run --rm --network none "$SKILLS_VIDEO_ENGINE_IMAGE" python -c \
  "from kokoro import KPipeline; KPipeline(lang_code='a', repo_id='hexgrad/Kokoro-82M'); print('Kokoro model ready')"
docker run --rm "$SKILLS_VIDEO_ENGINE_IMAGE" ffmpeg -hide_banner -encoders |
  grep -q libx264
docker run --rm "$SKILLS_VIDEO_ENGINE_IMAGE" chrome-headless-shell --version
```

## Use

Run every command from the video-project root. The canonical runtime contract
mounts that root at `/project`, uses an explicit working directory, preserves
the underlying command's exit status, and disables runtime networking.

Copy the image-bundled GSAP runtime into a new or existing project without
network access:

```bash
docker run --rm --network none \
  --volume "$PWD:/project" \
  --workdir /project \
  "$SKILLS_VIDEO_ENGINE_IMAGE" \
  copy-gsap video/assets/gsap.min.js
```

Generate narration with a project-owned script:

```bash
docker run --rm \
  --init \
  --shm-size=1g \
  --network none \
  --user "$(id -u):$(id -g)" \
  --volume "$PWD:/project" \
  --workdir /project \
  "$SKILLS_VIDEO_ENGINE_IMAGE" \
  python tools/tts_generate.py
```

### Batch narration with `tts-batch`

For multi-segment narration, the engine ships `tts-batch`: a manifest-driven
orchestrator built for memory-constrained hosts and interrupted runs. It
synthesizes one segment at a time, streams audio to disk as it is produced
(never holding a full narration in memory), and checkpoints progress after
every segment so a killed run resumes where it stopped.

Describe the narration in a project-owned manifest, for example
`narration.json`:

```json
{
  "schema_version": 1,
  "defaults": {"voice": "af_heart", "speed": 1.1},
  "segments": [
    {"id": "scene-01", "text": "A portable engine narrates in segments."},
    {"id": "scene-02", "text": "Each scene can override the voice.", "voice": "af_bella"}
  ]
}
```

Generate all pending segments; add a Docker memory limit on constrained hosts:

```bash
docker run --rm \
  --init \
  --network none \
  --memory 2g \
  --user "$(id -u):$(id -g)" \
  --volume "$PWD:/project" \
  --workdir /project \
  "$SKILLS_VIDEO_ENGINE_IMAGE" \
  tts-batch narration.json --output-dir video/assets/audio/segments
```

Each segment becomes `<id>.wav` (24 kHz mono PCM16) alongside
`tts-state.json`, which records a content fingerprint and measured duration
per segment. Re-running skips segments whose text and voice settings are
unchanged; editing a segment regenerates only that segment. `tts-batch`
exits `0` when every segment is complete and `10` when work remains, so
`--limit N` slices a large batch into bounded runs:

```bash
status=10
while [ "$status" -eq 10 ]; do
  docker run --rm --init --network none --memory 2g \
    --user "$(id -u):$(id -g)" --volume "$PWD:/project" --workdir /project \
    "$SKILLS_VIDEO_ENGINE_IMAGE" \
    tts-batch narration.json --output-dir video/assets/audio/segments --limit 5
  status=$?
done
```

`--dry-run` reports segment status without loading the model, and `--force`
regenerates everything. Compositions can read per-segment durations from
`tts-state.json` instead of re-measuring the audio.

Run the HyperFrames validation ladder from `/project/video`:

```bash
docker run --rm \
  --init \
  --shm-size=1g \
  --network none \
  --user "$(id -u):$(id -g)" \
  --volume "$PWD:/project" \
  --workdir /project/video \
  "$SKILLS_VIDEO_ENGINE_IMAGE" \
  hyperframes lint
```

```bash
docker run --rm \
  --init \
  --shm-size=1g \
  --network none \
  --user "$(id -u):$(id -g)" \
  --volume "$PWD:/project" \
  --workdir /project/video \
  "$SKILLS_VIDEO_ENGINE_IMAGE" \
  hyperframes check
```

```bash
docker run --rm \
  --init \
  --shm-size=1g \
  --network none \
  --user "$(id -u):$(id -g)" \
  --volume "$PWD:/project" \
  --workdir /project/video \
  "$SKILLS_VIDEO_ENGINE_IMAGE" \
  hyperframes snapshot --at 3,15,30 --output ../production/snapshots
```

```bash
docker run --rm \
  --init \
  --shm-size=1g \
  --network none \
  --user "$(id -u):$(id -g)" \
  --volume "$PWD:/project" \
  --workdir /project/video \
  "$SKILLS_VIDEO_ENGINE_IMAGE" \
  hyperframes render --output ../production/renders/master.mp4
```

Inspect the result from the project root:

```bash
docker run --rm \
  --init \
  --network none \
  --user "$(id -u):$(id -g)" \
  --volume "$PWD:/project" \
  --workdir /project \
  "$SKILLS_VIDEO_ENGINE_IMAGE" \
  ffprobe -v error -show_format -show_streams \
  production/renders/master.mp4
```

Measure narration and music levels:

```bash
docker run --rm \
  --init \
  --network none \
  --user "$(id -u):$(id -g)" \
  --volume "$PWD:/project" \
  --workdir /project \
  "$SKILLS_VIDEO_ENGINE_IMAGE" \
  ffmpeg -i production/renders/master.mp4 \
  -af volumedetect -f null -
```

Extract a review frame without exposing a host-absolute path to the container:

```bash
mkdir -p production/checkpoints/frames
docker run --rm \
  --init \
  --network none \
  --user "$(id -u):$(id -g)" \
  --volume "$PWD:/project" \
  --workdir /project \
  "$SKILLS_VIDEO_ENGINE_IMAGE" \
  ffmpeg -y -ss 3 -i production/renders/master.mp4 \
  -frames:v 1 production/checkpoints/frames/qa-3.png
```

On SELinux hosts, append `:Z` to the volume mount. The `--user` option keeps
generated files owned by the current host user. Do not mount the Docker
socket, home directory, credentials, or unrelated host paths.

The `/project` workdir, documented commands on `PATH`, offline Kokoro cache,
and mounted-project output behavior remain backward compatible within an
engine minor release. Breaking this contract requires a new minor release.

### Windows 11 usage

Docker Desktop and PowerShell are sufficient. The explainer-video skill ships
a native `engine.ps1` launcher, so Windows users do not need WSL or a local
checkout of this repository.

```powershell
cd $env:USERPROFILE\my-explainer-video
docker pull ghcr.io/mhuot/skills-video-engine:0.3.1
docker run --rm ghcr.io/mhuot/skills-video-engine:0.3.1 hyperframes --version
& .\tools\engine.ps1 -Workdir video hyperframes check
```

Notes / troubleshooting:

- Ensure Docker Desktop is configured with enough CPU and RAM for headless
  Chromium and model operations.
- If an organizational policy blocks public CDNs, use image `0.3.1` or newer;
  `copy-gsap` obtains the pinned runtime from the image with networking disabled.

## Build locally

```bash
docker build -t skills-video-engine:local .
bash scripts/smoke_test.sh skills-video-engine:local
bash scripts/e2e_test.sh skills-video-engine:local
```

The build downloads and caches the pinned Kokoro model revision. It also
includes the corresponding Debian source packages for FFmpeg and x264 under
`/usr/src/third-party`.

## Image footprint and component metadata

The published `0.2.0` reference image is approximately:

| Platform | Compressed layers | Local unpacked size |
| --- | ---: | ---: |
| Linux AMD64 | 4.18 GiB | Varies by container runtime |
| Linux ARM64 | 4.08 GiB | 7.50 GiB on Docker Desktop for Apple Silicon |

Image labels expose the pinned HyperFrames, Kokoro, model, AMD64
Chrome-for-Testing, and ARM64 Playwright versions:

```bash
docker image inspect "$SKILLS_VIDEO_ENGINE_IMAGE" --format '{{json .Config.Labels}}'
```

Release notes record the image digest and measured sizes for each release.

## Releases

Git tags matching `v*` publish these GHCR tags:

- Full semantic version, such as `0.1.0`
- Major/minor version, such as `0.1`
- Git SHA
- `latest`

Published images include an SBOM and build-provenance attestations.

## License

Project source is MIT licensed. Container components retain their own licenses;
see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
