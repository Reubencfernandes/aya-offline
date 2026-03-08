#!/usr/bin/env bash
# Build Aya inference engine as a WASM module using Emscripten.
#
# Prerequisites:
#   - Install Emscripten SDK: https://emscripten.org/docs/getting_started/downloads.html
#   - Activate it: source emsdk_env.sh
#
# Usage:
#   bash build_wasm.sh
#
# Output:
#   build/aya_engine.js
#   build/aya_engine.wasm

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$SCRIPT_DIR/src"
BUILD_DIR="$SCRIPT_DIR/build"

# Find emcc: try command first, then fall back to emcc.py via python
EMCC=""
if command -v emcc &> /dev/null; then
    EMCC="emcc"
elif [ -f "/c/emsdk/upstream/emscripten/emcc.py" ]; then
    EMCC="python /c/emsdk/upstream/emscripten/emcc.py"
elif [ -f "C:/emsdk/upstream/emscripten/emcc.py" ]; then
    EMCC="python C:/emsdk/upstream/emscripten/emcc.py"
else
    echo "ERROR: emcc not found. Install and activate the Emscripten SDK first."
    exit 1
fi

mkdir -p "$BUILD_DIR"

echo "=== Building Aya WASM engine ==="
echo "Source:  $SRC_DIR"
echo "Output:  $BUILD_DIR/aya_engine.js + aya_engine.wasm"
echo ""

$EMCC \
    "$SRC_DIR/gguf.c" \
    "$SRC_DIR/model.c" \
    "$SRC_DIR/aya_api.c" \
    -o "$BUILD_DIR/aya_engine.js" \
    -I"$SRC_DIR" \
    -O2 \
    -DAYA_WASM=1 \
    -s WASM=1 \
    -s ALLOW_MEMORY_GROWTH=1 \
    -s MAXIMUM_MEMORY=4GB \
    -s EXPORTED_FUNCTIONS='["_aya_init_buffer","_aya_generate","_aya_free_string","_aya_free","_malloc","_free"]' \
    -s EXPORTED_RUNTIME_METHODS='["ccall","cwrap","UTF8ToString","stringToUTF8","lengthBytesUTF8","wasmMemory"]' \
    -s MODULARIZE=1 \
    -s EXPORT_NAME='AyaModule'

echo ""
echo "=== Build complete ==="
ls -lh "$BUILD_DIR/aya_engine.js" "$BUILD_DIR/aya_engine.wasm" "$BUILD_DIR/aya_engine.worker.js" 2>/dev/null
