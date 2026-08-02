#!/usr/bin/env bash
set -euo pipefail

# Codex Termux zero-configuration launcher.
# It prefers the packaged Android binary, then a local build, then falls back
# to compiling the Rust CLI from source when a platform package is unavailable.

ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_BIN="$ROOT_DIR/npm-package/bin/codex.bin"
ANDROID_BIN="$ROOT_DIR/codex-rs/target/aarch64-linux-android/release/codex"
HOST_BIN="$ROOT_DIR/codex-rs/target/release/codex"
RUNTIME_VERSION="0.146.0"
RUNTIME_ROOT="$ROOT_DIR/.codex-termux-runtime/$RUNTIME_VERSION"
RUNTIME_BIN="$RUNTIME_ROOT/package/bin/codex.bin"
RUNTIME_LIB="$RUNTIME_ROOT/package/bin/libc++_shared.so"
RUNTIME_URL="https://registry.npmjs.org/@mmmbuto/codex-cli-termux/-/codex-cli-termux-${RUNTIME_VERSION}.tgz"
RUNTIME_SHA512_HEX="6db217db7b73fd59c168bef275d27195313af55bbc84a5ba096000679650e473b25926a258bbd959f73cb651e39ffb0893de9d5e7c4677d9023e7964c465cd8a"

chmod +x "$ROOT_DIR/start.sh" 2>/dev/null || true
for launcher in "$ROOT_DIR"/npm-package/bin/codex "$ROOT_DIR"/npm-package/bin/codex-exec; do
  [ -e "$launcher" ] && chmod +x "$launcher" 2>/dev/null || true
done

warn_missing() {
  printf 'Warning: %s is not installed or not available in PATH.\n' "$1" >&2
}

download_runtime() {
  [ -x "$RUNTIME_BIN" ] && [ -f "$RUNTIME_LIB" ] && return 0

  local downloader archive digest
  if command -v curl >/dev/null 2>&1; then
    downloader="curl"
  elif command -v wget >/dev/null 2>&1; then
    downloader="wget"
  else
    warn_missing "curl or wget (required for the verified Android binary)"
    return 1
  fi
  command -v tar >/dev/null 2>&1 || {
    warn_missing "tar (required for the verified Android binary)"
    return 1
  }
  command -v sha512sum >/dev/null 2>&1 || {
    warn_missing "sha512sum (required to verify the Android binary)"
    return 1
  }

  archive="$RUNTIME_ROOT/codex-termux-${RUNTIME_VERSION}.tgz"
  mkdir -p "$RUNTIME_ROOT"
  printf 'Downloading verified Codex Termux Android ARM64 runtime %s...\n' "$RUNTIME_VERSION" >&2
  if [ "$downloader" = "curl" ]; then
    curl --fail --location --silent --show-error --retry 3 "$RUNTIME_URL" -o "$archive"
  else
    wget --quiet --tries=3 "$RUNTIME_URL" -O "$archive"
  fi

  digest="$(sha512sum "$archive" | awk '{print $1}')"
  [ "$digest" = "$RUNTIME_SHA512_HEX" ] || {
    rm -f "$archive"
    printf 'Error: downloaded runtime failed SHA-512 verification.\n' >&2
    return 1
  }

  rm -rf "$RUNTIME_ROOT/package"
  tar -xzf "$archive" -C "$RUNTIME_ROOT"
  rm -f "$archive"
  chmod 0755 "$RUNTIME_BIN"
  chmod 0644 "$RUNTIME_LIB"
  [ -x "$RUNTIME_BIN" ] && [ -f "$RUNTIME_LIB" ] || {
    printf 'Error: verified runtime archive is missing the Android binary or libc++.\n' >&2
    return 1
  }
}

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
  elif [ -x "$RUNTIME_BIN" ] && [ -f "$RUNTIME_LIB" ]; then
    printf 'launcher=verified-download\n'
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

if download_runtime; then
  run_binary "$RUNTIME_BIN" login
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

warn_missing "Rust/Cargo (required because the verified Android runtime could not be downloaded)"
cat >&2 <<'EOF'
Unable to start Codex.
Install Node.js and the published Termux package, or install Rust/Cargo to use
the source fallback:

  npm install -g @mmmbuto/codex-cli-termux@latest
  ./start.sh
EOF
exit 1