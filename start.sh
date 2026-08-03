#!/usr/bin/env bash
set -euo pipefail

# Codex Termux zero-configuration launcher.
# It prefers the verified GitHub Actions Android runtime so Termux users do not
# need a Rust/NDK toolchain. Set CODEX_USE_SOURCE=1 only for local development.

ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_BIN="$ROOT_DIR/npm-package/bin/codex.bin"
ANDROID_BIN="$ROOT_DIR/codex-rs/target/aarch64-linux-android/release/codex"
HOST_BIN="$ROOT_DIR/codex-rs/target/release/codex"
RUNTIME_VERSION="termux-latest"
RUNTIME_ROOT="$ROOT_DIR/.codex-termux-runtime/$RUNTIME_VERSION"
RUNTIME_BIN="$RUNTIME_ROOT/package/bin/codex.bin"
RUNTIME_LIB="$RUNTIME_ROOT/package/bin/libc++_shared.so"
RUNTIME_CACHED_SHA512="$RUNTIME_ROOT/runtime.sha512"
RUNTIME_URL="https://github.com/ThT0AltayHR/codex-termux/releases/download/${RUNTIME_VERSION}/codex-termux-runtime.tgz"
RUNTIME_SHA512_URL="https://github.com/ThT0AltayHR/codex-termux/releases/download/${RUNTIME_VERSION}/codex-termux-runtime.tgz.sha512"
CODEX_PREFER_SOURCE="${CODEX_PREFER_SOURCE:-0}"

chmod +x "$ROOT_DIR/start.sh" 2>/dev/null || true
for launcher in "$ROOT_DIR"/npm-package/bin/codex "$ROOT_DIR"/npm-package/bin/codex-exec; do
  [ -e "$launcher" ] && chmod +x "$launcher" 2>/dev/null || true
done

warn_missing() {
  printf 'Warning: %s is not installed or not available in PATH.\n' "$1" >&2
}

download_runtime() {
  local downloader archive checksum_file expected_digest digest remote_checksum
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

  if [ -x "$RUNTIME_BIN" ] && [ -f "$RUNTIME_LIB" ] && [ -f "$RUNTIME_CACHED_SHA512" ]; then
    remote_checksum="$(mktemp)"
    if [ "$downloader" = "curl" ]; then
      if curl --fail --location --silent --show-error --connect-timeout 3 --max-time 8 "$RUNTIME_SHA512_URL" -o "$remote_checksum"; then
        expected_digest="$(awk 'NF {print $1; exit}' "$remote_checksum")"
        if [ "$expected_digest" = "$(cat "$RUNTIME_CACHED_SHA512")" ]; then
          rm -f "$remote_checksum"
          return 0
        fi
      else
        rm -f "$remote_checksum"
        return 0
      fi
    elif wget --timeout=3 --tries=1 --quiet "$RUNTIME_SHA512_URL" -O "$remote_checksum"; then
      expected_digest="$(awk 'NF {print $1; exit}' "$remote_checksum")"
      if [ "$expected_digest" = "$(cat "$RUNTIME_CACHED_SHA512")" ]; then
        rm -f "$remote_checksum"
        return 0
      fi
    else
      rm -f "$remote_checksum"
      return 0
    fi
    rm -f "$remote_checksum"
    rm -rf "$RUNTIME_ROOT/package"
    rm -f "$RUNTIME_CACHED_SHA512"
  fi

  archive="$RUNTIME_ROOT/codex-termux-${RUNTIME_VERSION}.tgz"
  checksum_file="$RUNTIME_ROOT/codex-termux-${RUNTIME_VERSION}.tgz.sha512"
  mkdir -p "$RUNTIME_ROOT"
  printf 'GitHub Actions tarafından hazırlanmış ARM64 runtime indiriliyor...\n' >&2
  if [ "$downloader" = "curl" ]; then
    curl --fail --location --silent --show-error --retry 3 "$RUNTIME_URL" -o "$archive"
    curl --fail --location --silent --show-error --retry 3 "$RUNTIME_SHA512_URL" -o "$checksum_file"
  else
    wget --quiet --tries=3 "$RUNTIME_URL" -O "$archive"
    wget --quiet --tries=3 "$RUNTIME_SHA512_URL" -O "$checksum_file"
  fi

  expected_digest="$(awk 'NF {print $1; exit}' "$checksum_file")"
  digest="$(sha512sum "$archive" | awk '{print $1}')"
  [ -n "$expected_digest" ] && [ "$digest" = "$expected_digest" ] || {
    rm -f "$archive" "$checksum_file"
    printf 'Error: GitHub runtime SHA-512 doğrulaması başarısız.\n' >&2
    return 1
  }

  rm -rf "$RUNTIME_ROOT/package"
  tar -xzf "$archive" -C "$RUNTIME_ROOT"
  rm -f "$archive" "$checksum_file"
  printf '%s\n' "$expected_digest" > "$RUNTIME_CACHED_SHA512"
  chmod 0755 "$RUNTIME_BIN"
  chmod 0644 "$RUNTIME_LIB"
  [ -x "$RUNTIME_BIN" ] && [ -f "$RUNTIME_LIB" ] || {
    printf 'Error: doğrulanmış runtime Android binary veya libc++ içermiyor.\n' >&2
    return 1
  }
}

prepare_binary() {
  local binary="$1"
  [ -x "$binary" ] || return 1
  export CODEX_SELF_EXE="$binary"
  if [ -n "${LD_LIBRARY_PATH:-}" ]; then
    export LD_LIBRARY_PATH="$(dirname "$binary"):$LD_LIBRARY_PATH"
  else
    export LD_LIBRARY_PATH="$(dirname "$binary")"
  fi
}

run_binary() {
  local binary="$1"
  shift
  prepare_binary "$binary"
  exec "$binary" "$@"
}

start_binary() {
  local binary="$1"
  shift
  prepare_binary "$binary"

  # Explicit CLI commands must be passed through unchanged. This keeps
  # `./start.sh help`, `doctor`, `config`, `login`, and `exec` useful even
  # before an interactive ChatGPT login has been completed.
  if [ "$#" -gt 0 ]; then
    exec "$binary" "$@"
  fi

  if ! "$binary" login status >/dev/null 2>&1; then
    printf 'Codex hesabı için giriş gerekiyor. Login ekranı açılıyor...\n' >&2
    "$binary" login
  fi

  printf 'Codex başlatılıyor...\n' >&2
  exec "$binary"
}

start_source_build() {
  if [ -x "$ANDROID_BIN" ]; then
    printf 'Yerel Android kaynak derlemesi başlatılıyor...\n' >&2
    start_binary "$ANDROID_BIN" "$@"
  fi

  if [ -x "$HOST_BIN" ]; then
    printf 'Yerel kaynak derlemesi başlatılıyor...\n' >&2
    start_binary "$HOST_BIN" "$@"
  fi

  if command -v cargo >/dev/null 2>&1 && [ -f "$ROOT_DIR/codex-rs/Cargo.toml" ]; then
    printf 'Fork özellikleri için Codex kaynak koddan derleniyor...\n' >&2
    exec cargo run --manifest-path "$ROOT_DIR/codex-rs/Cargo.toml" --release -p codex-cli -- "$@"
  fi

  return 1
}

if [ "${CODEX_USE_SOURCE:-0}" = "1" ]; then
  if start_source_build "$@"; then
    exit 0
  fi
  printf 'Error: CODEX_USE_SOURCE=1 seçildi ancak yerel kaynak derlemesi başlatılamadı.\n' >&2
  exit 1
fi

if [ "${CODEX_START_DRY_RUN:-0}" = "1" ]; then
  if [ "$CODEX_PREFER_SOURCE" = "1" ] && [ -x "$ANDROID_BIN" ]; then
    printf 'launcher=android-source-build\n'
  elif [ "$CODEX_PREFER_SOURCE" = "1" ] && [ -x "$HOST_BIN" ]; then
    printf 'launcher=host-source-build\n'
  elif [ -x "$PACKAGE_BIN" ]; then
    printf 'launcher=packaged\n'
  elif [ -x "$RUNTIME_BIN" ] && [ -f "$RUNTIME_LIB" ]; then
    printf 'launcher=verified-download\n'
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

if [ "$CODEX_PREFER_SOURCE" = "1" ]; then
  if [ -x "$ANDROID_BIN" ] || [ -x "$HOST_BIN" ] || {
    command -v cargo >/dev/null 2>&1 && [ -f "$ROOT_DIR/codex-rs/Cargo.toml" ];
  }; then
    start_source_build "$@"
  fi
fi

if download_runtime; then
  start_binary "$RUNTIME_BIN" "$@"
fi

if [ -x "$PACKAGE_BIN" ]; then
  start_binary "$PACKAGE_BIN" "$@"
fi

if command -v codex >/dev/null 2>&1; then
  if [ "$#" -gt 0 ]; then
    exec codex "$@"
  fi

  if ! codex login status >/dev/null 2>&1; then
    printf 'Codex hesabı için giriş gerekiyor. Login ekranı açılıyor...\n' >&2
    codex login
  fi

  printf 'Codex başlatılıyor...\n' >&2
  exec codex
fi

if command -v cargo >/dev/null 2>&1 && [ -f "$ROOT_DIR/codex-rs/Cargo.toml" ]; then
  start_source_build "$@"
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