# Image Digest Drift Check

This repository includes a local GitHub Action that detects whether a container tag now resolves to a different digest than the last accepted baseline.

## What it does

- Tracks one or more images in `.github/image-digest-lock.json`
- Resolves the current digest for each `name:tag`
- Fails the workflow when a stored digest no longer matches the current digest
- Lets you manually accept a new baseline when a change is intentional

## Files

- `.github/actions/check-image-digest-drift/action.yml`
- `.github/actions/check-image-digest-drift/check-image-digest-drift.sh`
- `.github/workflows/check-image-digest-drift.yml`
- `.github/image-digest-lock.json`

## How to use it

1. Update `.github/image-digest-lock.json` with the images and tags you care about.
2. Run the workflow manually with `mode=accept` the first time to record the current digests.
3. Let the scheduled workflow run in `check` mode to detect future drift.

## Lock file format

```json
{
  "images": [
    {
      "name": "ghcr.io/aquasecurity/trivy",
      "tag": "0.50.1",
      "digest": "sha256:..."
    }
  ]
}
```

## Notes

- This is most useful for versioned tags that are expected to be immutable.
- For intentionally moving tags, use the workflow dispatch `accept` mode to refresh the baseline.
