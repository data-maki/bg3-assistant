#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
rm -rf build dist/bg3-honor-backend
export UV_PYTHON="${UV_PYTHON:-3.11}"
uv sync --locked
uv run --with pyinstaller==6.21.0 pyinstaller \
  --noconfirm \
  --clean \
  --onedir \
  --name bg3-honor-backend \
  --paths . \
  --add-data "../data:data" \
  --add-data "app/static/map:backend/app/static/map" \
  --hidden-import uvicorn.logging \
  --hidden-import uvicorn.loops.auto \
  --hidden-import uvicorn.protocols.http.auto \
  --hidden-import uvicorn.protocols.websockets.auto \
  --hidden-import uvicorn.lifespan.on \
  launcher.py

test -x dist/bg3-honor-backend/bg3-honor-backend
echo "$PWD/dist/bg3-honor-backend"
