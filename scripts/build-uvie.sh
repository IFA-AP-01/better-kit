#!/bin/bash
# Builds the uvie-rs static library into Vendor/lib (skipped when it is already there).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIB="$ROOT/Vendor/lib/libuvie.a"
SRC="$ROOT/Vendor/uvie-rs"

if [[ -f "$LIB" && "${FORCE_UVIE:-0}" != "1" ]]; then
  exit 0
fi
if [[ ! -d "$SRC" ]]; then
  echo "error: $SRC missing. Run: git clone https://github.com/uvie-project/uvie-rs Vendor/uvie-rs" >&2
  exit 1
fi
export PATH="$HOME/.cargo/bin:$PATH"
cd "$SRC"
nice -n 10 cargo build --release --lib --target aarch64-apple-darwin
mkdir -p "$ROOT/Vendor/lib"
cp target/aarch64-apple-darwin/release/libuvie.a "$LIB"
cp include/uvie.h "$ROOT/Shared/uvie.h" 2>/dev/null || true
