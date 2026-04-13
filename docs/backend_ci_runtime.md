# LX32 Backend CI + Runtime Flow

This flow keeps LLVM backend builds in one stable CI environment and lets firmware developers use a lightweight runtime image.

## What CI produces

- Commit-versioned toolchain artifact:
  - `llc`
  - `llvm-mc`
  - `llvm-objcopy`
  - `ld.lld`
  - `lx32-llvm` shared libraries
  - `LX32_BACKEND_COMMIT` marker
- Runtime image in GHCR:
  - `ghcr.io/<owner>/lx32-runtime:<commit-sha>`
  - `ghcr.io/<owner>/lx32-runtime:latest` (for `main`)

Workflow file: `.github/workflows/backend-toolchain.yml`.

## Developer usage (no backend rebuild)

Use the runtime-only compose file:

```bash
docker compose -f docker-compose.runtime.yml pull

docker compose -f docker-compose.runtime.yml run --rm lx32 bash -lc 'cat /usr/local/share/LX32_BACKEND_COMMIT && make test-baremetal-deep'
```

Pin a specific commit-built toolchain image:

```bash
LX32_TOOLCHAIN_TAG=<commit-sha> docker compose -f docker-compose.runtime.yml run --rm lx32 bash -lc 'llc --version | head -n 8'
```

## Backend contributors

Backend contributors can still use the heavyweight local build flow (`Dockerfile`) when needed.

