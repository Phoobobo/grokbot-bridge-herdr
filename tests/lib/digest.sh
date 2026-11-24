# sha256 via sha256sum (Linux) or shasum (stock macOS). Source this; do not execute it as a test.
digest_setup() {
  if command -v sha256sum >/dev/null 2>&1; then
    DIGEST_BIN=$(command -v sha256sum)
    DIGEST_KIND=sha256sum
  elif command -v shasum >/dev/null 2>&1; then
    DIGEST_BIN=$(command -v shasum)
    DIGEST_KIND=shasum
  else
    echo "missing sha256sum or shasum" >&2
    return 1
  fi
}
digest_file() {
  if [ "$DIGEST_KIND" = sha256sum ]; then
    "$DIGEST_BIN" "$1" | awk '{print $1}'
  else
    "$DIGEST_BIN" -a 256 "$1" | awk '{print $1}'
  fi
}
digest_text() {
  if [ "$DIGEST_KIND" = sha256sum ]; then
    printf '%s' "$1" | "$DIGEST_BIN" | awk '{print $1}'
  else
    printf '%s' "$1" | "$DIGEST_BIN" -a 256 | awk '{print $1}'
  fi
}
