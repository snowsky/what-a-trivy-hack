#!/usr/bin/env bash

set -euo pipefail

LOCK_FILE="${1:-.github/image-digest-lock.json}"
MODE="${2:-check}"
WRITE_MISSING_DIGESTS="${3:-true}"

if [[ ! -f "$LOCK_FILE" ]]; then
  echo "Lock file not found: $LOCK_FILE" >&2
  exit 1
fi

if [[ "$MODE" != "check" && "$MODE" != "accept" ]]; then
  echo "Unsupported mode: $MODE" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required but not installed." >&2
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is required but not installed." >&2
  exit 1
fi

resolve_digest() {
  local image_ref="$1"

  docker buildx imagetools inspect "$image_ref" --format '{{json .Manifest.Digest}}' \
    | tr -d '"'
}

entry_count="$(jq '.images | length' "$LOCK_FILE")"
if [[ "$entry_count" -eq 0 ]]; then
  echo "No images found in $LOCK_FILE" >&2
  exit 1
fi

tmp_file="$(mktemp)"
cp "$LOCK_FILE" "$tmp_file"

checked_count=0
drift_detected=false
updated_lock_file=false

summary_file="${GITHUB_STEP_SUMMARY:-}"
if [[ -n "$summary_file" ]]; then
  {
    echo "## Image digest drift check"
    echo
    echo "| Image | Locked digest | Current digest | Result |"
    echo "| --- | --- | --- | --- |"
  } >>"$summary_file"
fi

for ((i = 0; i < entry_count; i++)); do
  image_name="$(jq -r ".images[$i].name" "$tmp_file")"
  image_tag="$(jq -r ".images[$i].tag" "$tmp_file")"
  locked_digest="$(jq -r ".images[$i].digest // \"\"" "$tmp_file")"

  if [[ -z "$image_name" || -z "$image_tag" || "$image_name" == "null" || "$image_tag" == "null" ]]; then
    echo "Entry $i is missing name or tag." >&2
    exit 1
  fi

  image_ref="${image_name}:${image_tag}"
  current_digest="$(resolve_digest "$image_ref")"

  if [[ -z "$current_digest" || "$current_digest" == "null" ]]; then
    echo "Could not resolve a digest for $image_ref" >&2
    exit 1
  fi

  result="ok"

  if [[ -z "$locked_digest" ]]; then
    result="missing baseline"
    if [[ "$WRITE_MISSING_DIGESTS" == "true" || "$MODE" == "accept" ]]; then
      jq --argjson idx "$i" --arg digest "$current_digest" \
        '.images[$idx].digest = $digest' "$tmp_file" >"${tmp_file}.next"
      mv "${tmp_file}.next" "$tmp_file"
      updated_lock_file=true
      locked_digest="(empty)"
    fi
  elif [[ "$locked_digest" != "$current_digest" ]]; then
    result="drift detected"
    drift_detected=true
    if [[ "$MODE" == "accept" ]]; then
      jq --argjson idx "$i" --arg digest "$current_digest" \
        '.images[$idx].digest = $digest' "$tmp_file" >"${tmp_file}.next"
      mv "${tmp_file}.next" "$tmp_file"
      updated_lock_file=true
      result="updated baseline"
    fi
  fi

  if [[ -n "$summary_file" ]]; then
    echo "| \`$image_ref\` | \`${locked_digest:-"(empty)"}\` | \`$current_digest\` | $result |" >>"$summary_file"
  fi

  checked_count=$((checked_count + 1))
done

if [[ "$updated_lock_file" == "true" ]]; then
  mv "$tmp_file" "$LOCK_FILE"
else
  rm -f "$tmp_file"
fi

{
  echo "checked-count=$checked_count"
  echo "drift-detected=$drift_detected"
  echo "updated-lock-file=$updated_lock_file"
} >>"$GITHUB_OUTPUT"

if [[ "$MODE" == "check" && "$drift_detected" == "true" ]]; then
  echo "One or more image digests drifted from the stored baseline." >&2
  exit 1
fi
