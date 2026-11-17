#!/bin/bash
# Offline tests of validate_dispatch. Needs bash only.

set -uo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SCRIPT=$ROOT/validate_dispatch
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

failures=0

fail()
{
    echo "FAIL: $*"
    failures=$((failures + 1))
}

# ok|bad <pkgname> <version> [image_src]
check()
{
    local want=$1 rc=0
    shift
    "$SCRIPT" "$@" >"$TMP/out" 2>&1 || rc=$?
    if [ "$want" = ok ] && [ "$rc" -ne 0 ]; then
        fail "refused: $(printf '%q ' "$@") ($(cat "$TMP/out"))"
    elif [ "$want" = bad ]; then
        [ "$rc" -eq 1 ] || fail "accepted or crashed (rc=$rc): $(printf '%q ' "$@")"
        grep -q '^::error::' "$TMP/out" || fail "no ::error:: message: $(printf '%q ' "$@")"
    fi
}

check ok calaos-server 4.8.3 ghcr.io/calaos/calaos_base:4.8.3
check ok calaos-server 4.8.2-dev.3 ghcr.io/calaos/calaos_base:4.8.2-dev.3
check ok calaos-server 4.8.2~dev.3 ghcr.io/calaos/calaos_base:4.8.2-dev.3
check ok calaos-server 4.8.3 ghcr.io/calaos/calaos_base:latest
check ok mosquitto 2.0.22.1 docker.io/library/eclipse-mosquitto:2.0.22.1
check ok haproxy 2.8.31 docker.io/library/haproxy:2.8.31-alpine
check ok envoy 1.0.5 ghcr.io/raoulh/envoy:1.0.5
check ok calaos-web-app 4.8.3
check ok grafana 11.6.16 docker.io/grafana/grafana:11.6.16
check ok calaos-keyring 1.0.0
check ok calaos-keyring 1.0.0 ""

check bad "calaos-server;id" 4.8.3
check bad 'calaos-server$(id)' 4.8.3
check bad "calaos-server " 4.8.3
check bad "calaos server" 4.8.3
check bad Calaos-Server 4.8.3
check bad "" 4.8.3
check bad -server 4.8.3
check bad calaos-meta 4.8.3
check bad "calaos-meta " 4.8.3
check bad CALAOS-META 4.8.3
check bad "calaos-meta
x" 4.8.3
check bad calaos-server ""
check bad calaos-server 4.8.3-1
check bad calaos-server 2.0.22-1
check bad calaos-server 4.8.3 ghcr.io/evil/calaos_base:4.8.3
check bad calaos-server 4.8.3 ghcr.io/calaos/other:4.8.3
check bad calaos-server 4.8.3 docker.io/calaos/calaos_base:4.8.3
check bad calaos-server 4.8.3 ghcr.io/calaos/calaos_base
check bad calaos-server 4.8.3 ghcr.io/calaos/calaos_base:
check bad calaos-server 4.8.3 ghcr.io/calaos/calaos_base:a:b
check bad calaos-keyring 1.0.0 ghcr.io/calaos/calaos_base:1.0.0
check bad tests 1.0.0
check bad .. 1.0.0
check bad nonexistent 1.0.0
check bad calaos-server "4.8.3;id"
check bad calaos-server '4.8.3$(id)'
check bad calaos-server '4.8.3`id`'
check bad calaos-server "4.8.3 "
check bad calaos-server "4.8.3
5"
check bad calaos-server "4.8.3/../x"
check bad calaos-server "v4.8.3"
check bad calaos-server "4.8.3-evil"
check bad calaos-server 4.8.3 "ghcr.io/calaos/calaos_base:4.8.3;id"
check bad calaos-server 4.8.3 'ghcr.io/calaos/calaos_base:$(id)'
check bad calaos-server 4.8.3 "ghcr.io/calaos/calaos_base:1|s"
check bad calaos-server 4.8.3 "ghcr.io/calaos/calaos_base:1 y"
check bad calaos-server 4.8.3 "ghcr.io/calaos/calaos_base:1&y"
check bad calaos-server 4.8.3 "evil.example/calaos/x:1"
check bad calaos-server 4.8.3 "ghcr.io/calaos/x"
check bad calaos-server 4.8.3 "ghcr.io/Calaos/x:1"
check bad calaos-server
check bad calaos-server 4.8.3 ghcr.io/calaos/calaos_base:1 extra

check bad --image-required calaos-server 4.8.3
check bad --image-required calaos-server 4.8.3 ""
check ok --image-required calaos-server 4.8.3 ghcr.io/calaos/calaos_base:4.8.3
check ok --image-required calaos-keyring 1.0.0
check ok --image-required calaos-web-app 4.8.3 ""

# Replay the exact step of build_deb.yml (the dispatch path) with a payload.
# ok|bad <pkgname> <version> <image_src>
replay()
{
    local want=$1 cmd rc=0
    cmd=$(sed -n 's/^ *run: \(\.\/validate_dispatch .*\)$/\1/p' "$ROOT/.github/workflows/build_deb.yml")
    [ -n "$cmd" ] || { fail "validate step not found in build_deb.yml"; return; }
    (cd "$ROOT" && PKGNAME=$2 VERSION=$3 IMAGE_SRC=$4 bash -c "$cmd") >"$TMP/out" 2>&1 || rc=$?
    if [ "$want" = ok ] && [ "$rc" -ne 0 ]; then
        fail "replay refused: $(printf '%q ' "${@:2}")"
    elif [ "$want" = bad ] && [ "$rc" -ne 1 ]; then
        fail "replay accepted or crashed (rc=$rc): $(printf '%q ' "${@:2}")"
    fi
}

replay ok calaos-server 4.8.3 ghcr.io/calaos/calaos_base:4.8.3
replay ok calaos-home 4.8.3 ghcr.io/calaos/calaos_home:4.8.3
replay ok calaos-web-app 4.8.3 ""
# The flag must not be consumable from the payload (arguments shifted by one).
replay bad --image-required calaos-keyring 4.8.3
replay bad --image-required --image-required calaos-keyring

# Tag length: at most 128 characters.
tag128=$(printf 'a%.0s' $(seq 128))
check ok calaos-server 4.8.3 "ghcr.io/calaos/calaos_base:$tag128"
check bad calaos-server 4.8.3 "ghcr.io/calaos/calaos_base:${tag128}a"

# A registry with a port: only the last :tag is dropped to get the repository.
mkdir -p "$TMP/fake/portpkg/debian"
cp "$SCRIPT" "$TMP/fake/validate_dispatch"
touch "$TMP/fake/portpkg/debian/control"
echo 'IMAGE_SRC?=localhost:5000/calaos/x:$(VERSION)' >"$TMP/fake/portpkg/Makefile"
SCRIPT=$TMP/fake/validate_dispatch
check ok portpkg 1.0.0 localhost:5000/calaos/x:1.0.0
check bad portpkg 1.0.0 localhost:5000/evil/x:1.0.0
check bad portpkg 1.0.0 localhost:6000/calaos/x:1.0.0
check bad portpkg 1.0.0 localhost:5000/calaos/x

if [ "$failures" -ne 0 ]; then
    echo "$failures failure(s)"
    exit 1
fi
echo "validate_dispatch: all tests passed"
