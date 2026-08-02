#!/usr/bin/env bash
set -euo pipefail

# Codex Termux zero-configuration launcher.
# It prefers the packaged Android binary, then a local build, then falls back
# to compiling the Rust CLI from source when a platform package is unavailable.

ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_BIN="$ROOT_DIR/npm-package/bin/codex.bin"
ANDROID_BIN="$ROOT_DIR/codex-rs/target/aarch64-linux-android/release/codex"
HOST_BIN="$ROOT_DIR/codex-rs/target/release/codex"

chmod +x "$ROOT_DIR/start.sh" 2>/dev/null || true
for launcher in "$ROOT_DIR"/npm-package/bin/codex "$ROOT_DIR"/npm-package/bin/codex-exec; do
  [ -e "$launcher" ] && chmod +x "$launcher" 2>/dev/null || true
done

warn_missing() {
  printf 'Warning: %s is not installed or not available in PATH.\n' "$1" >&2
}

command -v node >/dev/null 2>&1 || warn_missing "Node.js (required by the npm launcher)"
command -v rustc >/dev/null 2>&1 || warn_missing "Rust (required only for the source fallback)"
command -v cargo >/dev/null 2>&1 || warn_missing "Cargo (required only for the source fallback)"

run_binary() {
  local binary="$1"
  shift
  [ -x "$binary" ] || return 1
  export CODEX_SELF_EXE="$binary"
  if [ -n "${LD_LIBRARY_PATH:-}" ]; then
    export LD_LIBRARY_PATH="$(dirname "$binary"):$LD_LIBRARY_PATH"
  else
    export LD_LIBRARY_PATH="$(dirname "$binary")"
  fi
  exec "$binary" "$@"
}

if [ "${CODEX_START_DRY_RUN:-0}" = "1" ]; then
  if [ -x "$PACKAGE_BIN" ]; then
    printf 'launcher=packaged\n'
  elif [ -x "$ANDROID_BIN" ]; then
    printf 'launcher=android-source-build\n'
  elif [ -x "$HOST_BIN" ]; then
    printf 'launcher=host-source-build\n'
  elif command -v codex >/dev/null 2>&1; then
    printf 'launcher=PATH-codex\n'
  elif command -v cargo >/dev/null 2>&1; then
    printf 'launcher=cargo-source-fallback\n'
  else
    printf 'launcher=unavailable\n'
    exit 1
  fi
  exit 0
fi

if [ -x "$PACKAGE_BIN" ]; then
  run_binary "$PACKAGE_BIN" login
fi

if [ -x "$ANDROID_BIN" ]; then
  run_binary "$ANDROID_BIN" login
fi

if [ -x "$HOST_BIN" ]; then
  run_binary "$HOST_BIN" login
fi

if command -v codex >/dev/null 2>&1; then
  exec codex login
fi

if command -v cargo >/dev/null 2>&1 && [ -f "$ROOT_DIR/codex-rs/Cargo.toml" ]; then
  printf 'No packaged Codex binary was found; compiling and launching the source CLI.\n' >&2
  exec cargo run --manifest-path "$ROOT_DIR/codex-rs/Cargo.toml" --release -p codex-cli -- login
fi

cat >&2 <<'EOF'
Unable to start Codex.
Install Node.js and the published Termux package, or install Rust/Cargo to use
the source fallback:

  npm install -g @mmmbuto/codex-cli-termux@latest
  ./start.sh
EOF
exit 1