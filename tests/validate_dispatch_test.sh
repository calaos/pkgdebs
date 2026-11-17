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

if [ "$failures" -ne 0 ]; then
    echo "$failures failure(s)"
    exit 1
fi
echo "validate_dispatch: all tests passed"
