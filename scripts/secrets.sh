#!/bin/sh
# Copy the DeepSeek key the casino host uses into the two places that read
# it, both gitignored:
#   .env                  the skee CLI (skee haggle)
#   App/Secrets.xcconfig  the iOS app, via App/Info.plist
# The key comes from $DEEPSEEK_API_KEY, else ../marginalia/.env, the same
# key marginalia uses.
set -eu
cd "$(dirname "$0")/.."
key="${DEEPSEEK_API_KEY:-}"
if [ -z "$key" ] && [ -f ../marginalia/.env ]; then
  key=$(sed -n 's/^DEEPSEEK_API_KEY=//p' ../marginalia/.env | tr -d "\"' ")
fi
if [ -z "$key" ]; then
  echo "no DeepSeek key: set DEEPSEEK_API_KEY or add it to ../marginalia/.env" >&2
  exit 1
fi
umask 077
printf 'DEEPSEEK_API_KEY=%s\n' "$key" > .env
# xcconfig reads // as a comment; the key has none, but say so loudly if it ever does.
case "$key" in */*) echo "key contains '/', which xcconfig would mangle" >&2; exit 1;; esac
printf 'DEEPSEEK_API_KEY = %s\n' "$key" > App/Secrets.xcconfig
echo "wrote .env and App/Secrets.xcconfig"
