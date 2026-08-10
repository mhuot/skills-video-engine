#!/usr/bin/env bash
set -euo pipefail

container_workdir="/project"
if [[ "${1:-}" == "--workdir" ]]; then
  if [[ $# -lt 3 ]]; then
    echo "Usage: $0 [--workdir relative/path] <engine command> [arguments...]" >&2
    exit 2
  fi
  requested_workdir="$2"
  shift 2
  if [[ "${requested_workdir}" == /* || "${requested_workdir}" == *".."* ]]; then
    echo "Workdir must be a relative path beneath the video project" >&2
    exit 2
  fi
  container_workdir="/project/${requested_workdir#./}"
fi

if [[ $# -eq 0 ]]; then
  echo "Usage: $0 [--workdir relative/path] <engine command> [arguments...]" >&2
  echo "Example: $0 --workdir video hyperframes check" >&2
  exit 2
fi

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
project_dir="${VIDEO_PROJECT_DIR:-${PWD}}"

if [[ ! -d "${project_dir}" ]]; then
  echo "Video project directory not found: ${project_dir}" >&2
  exit 1
fi

resolved_project_dir="$(cd "${project_dir}" && pwd)"
export VIDEO_PROJECT_DIR="${resolved_project_dir}"
export ENGINE_UID="${ENGINE_UID:-$(id -u)}"
export ENGINE_GID="${ENGINE_GID:-$(id -g)}"

exec docker compose -f "${repository_root}/compose.yaml" run --rm \
  --workdir "${container_workdir}" engine "$@"
