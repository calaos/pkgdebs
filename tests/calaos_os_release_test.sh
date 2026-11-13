#!/bin/bash
# Offline tests of calaos_os_release. Needs bash, awk and dpkg: run them with
# `make test` (builder image) or directly on a Debian/Ubuntu host.

set -uo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SCRIPT=$ROOT/calaos_os_release
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export CALAOS_OS_RELEASE_DATE="Fri, 13 Nov 2026 12:00:00 +0000"

failures=0
count=0

fail()
{
    echo "FAIL: $*"
    failures=$((failures + 1))
}

# stanza <package> <version>
stanza()
{
    printf 'Package: %s\nVersion: %s\nArchitecture: all\nDescription: x\n\n' "$1" "$2"
}

# The published state of a channel, split across repositories and components
# like the real indexes. Versions are out of order on purpose.
make_index()
{
    local dir=$1
    mkdir -p "$dir"
    {
        stanza calaos-server 4.8.1
        stanza calaos-server 4.10.0
        stanza calaos-server 4.9.0
        stanza calaos-home 4.5.2
        stanza calaos-web-app 4.2.0
        stanza calaos-keyring 1.0.0
        stanza calaos-haproxy 2.8.31
        stanza calaos 1.1.4
        stanza unrelated-package 99.0
    } >"$dir/pkgdebs.releases.all"
    {
        stanza calaos-server 4.11.0~dev.2
        stanza calaos-web-app 4.2.1~dev.0
    } >"$dir/pkgdebs.pre-releases.all"
    {
        printf 'Package: calaos-container\nVersion: 1.9.1-0~bookworm0\nArchitecture: amd64\n\n'
        printf 'Package: calaos-container\nVersion: 1.10.0~dev.1-0~bookworm0\nArchitecture: amd64\n'
    } >"$dir/calaos-container.releases.amd64"
    : >"$dir/calaos-container.releases.arm64"
}

make_meta()
{
    local dir=$1
    mkdir -p "$dir/debian"
    cat >"$dir/debian/control" <<'EOF'
Source: calaos
Section: admin
Build-Depends: debhelper (>= 11), pkgconf

Package: calaos
Architecture: all
Description: Meta package for Calaos-OS
 This package is the Calaos meta package that pulls all calaos dependencies
Depends: calaos-keyring,
         calaos-container,
         calaos-server,
         calaos-web-app,
         ola, chrony
EOF
    cat >"$dir/debian/changelog" <<'EOF'
calaos (1.2.3) UNRELEASED; urgency=medium

  * Initial release

 -- Calaos Team <team@calaos.fr>  Sat, 01 Jul 2023 00:00:00 +0200
EOF
}

# run <name> <expected rc> <args...>: output in $OUT, stderr in $ERR
run()
{
    local name=$1 want=$2 rc
    shift 2
    count=$((count + 1))
    "$SCRIPT" "$@" >"$TMP/out" 2>"$TMP/err"
    rc=$?
    OUT=$(cat "$TMP/out")
    ERR=$(cat "$TMP/err")
    if [[ $want == ok && $rc -ne 0 ]]; then
        fail "$name: rc $rc, stderr: $ERR"
        return 1
    fi
    if [[ $want == ko && $rc -eq 0 ]]; then
        fail "$name: accepted, expected a refusal"
        return 1
    fi
    return 0
}

expect_contains()
{
    local name=$1 haystack=$2 needle=$3
    [[ $haystack == *"$needle"* ]] || fail "$name: missing '$needle' in: $haystack"
}

fresh()
{
    rm -rf "$TMP/case"
    make_index "$TMP/case/index"
    make_meta "$TMP/case/meta"
}

# Format refused, per channel.
for v in 2026.13 2026.00 2026.1 26.11 2026.11.0 2026.11.01 2026.11~dev.1 \
    2026.11-dev.1 1.2.3 2026.11.1a "" "2026.11 "; do
    fresh
    run "stable refuses '$v'" ko prepare stable "$v" "$TMP/case/index" "$TMP/case/meta" &&
        expect_contains "stable refuses '$v'" "$ERR" "not a stable Calaos OS version"
    cmp -s "$TMP/case/meta/debian/control" <(make_meta "$TMP/ref" && cat "$TMP/ref/debian/control") ||
        fail "stable refuses '$v': control modified"
done
for v in 2026.11 2026.11.1 2026.11~dev.01 2026.11~rc.1 2026.11.1~dev.1 \
    2026.11~dev 2026.13~dev.1 2026.11~dev.1~dev.2; do
    fresh
    run "dev refuses '$v'" ko prepare dev "$v" "$TMP/case/index" "$TMP/case/meta" &&
        expect_contains "dev refuses '$v'" "$ERR" "not a dev Calaos OS version"
done
fresh
run "unknown channel refused" ko prepare beta 2026.11 "$TMP/case/index" "$TMP/case/meta"

# Accepted formats, and the version/tag outputs.
for spec in "stable 2026.11 2026.11 2026.11" "stable 2026.11.2 2026.11.2 2026.11.2" \
    "dev 2026.11~dev.0 2026.11~dev.0 2026.11-dev.0" "dev 2026.12-dev.3 2026.12~dev.3 2026.12-dev.3"; do
    read -r ch v deb tag <<<"$spec"
    fresh
    if run "$ch accepts $v" ok prepare "$ch" "$v" "$TMP/case/index" "$TMP/case/meta"; then
        [[ $OUT == "version=$deb"$'\n'"tag_version=$tag" ]] || fail "$ch accepts $v: output '$OUT'"
        head -1 "$TMP/case/meta/debian/changelog" | grep -qxF "calaos ($deb) bookworm; urgency=medium" ||
            fail "$ch accepts $v: changelog header $(head -1 "$TMP/case/meta/debian/changelog")"
    fi
done

# Not strictly greater than the published calaos.
for spec in "stable 2026.11 2026.11" "stable 2026.11 2026.10" "stable 2026.11.2 2026.11.1" \
    "dev 2026.11 2026.11~dev.4" "dev 2026.12~dev.1 2026.12~dev.1" "dev 2026.12~dev.2 2026.12~dev.1"; do
    read -r ch published v <<<"$spec"
    fresh
    stanza calaos "$published" >>"$TMP/case/index/pkgdebs.releases.all"
    run "$ch refuses $v after $published" ko prepare "$ch" "$v" "$TMP/case/index" "$TMP/case/meta" &&
        expect_contains "$ch refuses $v after $published" "$ERR" "is not greater than the published calaos $published"
done
for spec in "stable 2026.11 2026.11.1" "stable 2026.11~dev.3 2026.11" "stable 2026.12 2027.01" \
    "dev 2026.11 2026.12~dev.0" "dev 2026.12~dev.1 2026.12~dev.2"; do
    read -r ch published v <<<"$spec"
    fresh
    stanza calaos "$published" >>"$TMP/case/index/pkgdebs.releases.all"
    run "$ch accepts $v after $published" ok prepare "$ch" "$v" "$TMP/case/index" "$TMP/case/meta"
done
# Without any published calaos, any well-formed version goes.
fresh
sed -i '/^Package: calaos$/,/^$/d' "$TMP/case/index/pkgdebs.releases.all"
run "first release accepted" ok prepare stable 2026.11 "$TMP/case/index" "$TMP/case/meta"

# Depends and changelog generated from the index.
fresh
if run "depends" ok prepare stable 2026.11 "$TMP/case/index" "$TMP/case/meta" "$TMP/case/notes.md"; then
    want_control=$(
        cat <<'EOF'
Source: calaos
Section: admin
Build-Depends: debhelper (>= 11), pkgconf

Package: calaos
Architecture: all
Description: Meta package for Calaos-OS
 This package is the Calaos meta package that pulls all calaos dependencies
Depends: calaos-keyring (>= 1.0.0),
         calaos-container (>= 1.10.0~dev.1-0~bookworm0),
         calaos-server (>= 4.11.0~dev.2),
         calaos-web-app (>= 4.2.1~dev.0),
         ola,
         chrony
EOF
    )
    [[ $(cat "$TMP/case/meta/debian/control") == "$want_control" ]] ||
        fail "depends: control is"$'\n'"$(cat "$TMP/case/meta/debian/control")"
    want_changelog=$(
        cat <<'EOF'
calaos (2026.11) bookworm; urgency=medium

  * Calaos OS 2026.11 (stable).
  * calaos-keyring 1.0.0
  * calaos-container 1.10.0~dev.1-0~bookworm0
  * calaos-server 4.11.0~dev.2
  * calaos-web-app 4.2.1~dev.0

 -- Calaos Team <team@calaos.fr>  Fri, 13 Nov 2026 12:00:00 +0000
EOF
    )
    [[ $(cat "$TMP/case/meta/debian/changelog") == "$want_changelog" ]] ||
        fail "depends: changelog is"$'\n'"$(cat "$TMP/case/meta/debian/changelog")"
    expect_contains "depends: notes" "$(cat "$TMP/case/notes.md")" "- calaos-server 4.11.0~dev.2"
fi

# The highest version wins whatever the order (dpkg ordering, not text).
fresh
rm "$TMP/case/index/pkgdebs.pre-releases.all"
stanza calaos-server 4.9.10 >>"$TMP/case/index/pkgdebs.releases.all"
if run "dpkg ordering" ok prepare stable 2026.11 "$TMP/case/index" "$TMP/case/meta"; then
    grep -qF "calaos-server (>= 4.10.0)," "$TMP/case/meta/debian/control" ||
        fail "dpkg ordering: $(grep calaos-server "$TMP/case/meta/debian/control")"
    grep -qF "calaos-web-app (>= 4.2.0)," "$TMP/case/meta/debian/control" ||
        fail "dpkg ordering: $(grep calaos-web-app "$TMP/case/meta/debian/control")"
fi

# A component missing from the channel is an error, not an unbounded Depends.
fresh
sed -i '/^Package: calaos-web-app$/,/^$/d' "$TMP/case/index/pkgdebs.releases.all" "$TMP/case/index/pkgdebs.pre-releases.all"
run "missing component" ko prepare stable 2026.11 "$TMP/case/index" "$TMP/case/meta" &&
    expect_contains "missing component" "$ERR" "not published in the stable channel: calaos-web-app"

# A calaos-* entry with its own constraint would escape the pin.
fresh
sed -i 's/calaos-server,/calaos-server (>= 4.0),/' "$TMP/case/meta/debian/control"
run "constrained entry" ko prepare stable 2026.11 "$TMP/case/index" "$TMP/case/meta" &&
    expect_contains "constrained entry" "$ERR" "already has a constraint"

fresh
rm -f "$TMP/case/index"/*
run "empty index dir" ko prepare stable 2026.11 "$TMP/case/index" "$TMP/case/meta"

# Index URLs: stable reads only the releases component.
cat >"$TMP/calaos.list" <<'EOF'
# comment
deb [signed-by=/usr/share/keyrings/k.gpg] https://deb.example/calaos/pkgdebs bookworm releases
deb https://deb.example/calaos/calaos_ddns/ bookworm releases
EOF
if run "urls stable" ok urls stable "$TMP/calaos.list"; then
    [[ $(wc -l <<<"$OUT") -eq 6 ]] || fail "urls stable: $OUT"
    expect_contains "urls stable" "$OUT" "pkgdebs.releases.all https://deb.example/calaos/pkgdebs/dists/bookworm/releases/binary-all/Packages"
    expect_contains "urls stable" "$OUT" "calaos_ddns.releases.arm64 https://deb.example/calaos/calaos_ddns/dists/bookworm/releases/binary-arm64/Packages"
    [[ $OUT != *pre-releases* ]] || fail "urls stable: reads pre-releases"
fi
if run "urls dev" ok urls dev "$TMP/calaos.list"; then
    [[ $(wc -l <<<"$OUT") -eq 12 ]] || fail "urls dev: $OUT"
    expect_contains "urls dev" "$OUT" "pkgdebs.pre-releases.amd64 https://deb.example/calaos/pkgdebs/dists/bookworm/pre-releases/binary-amd64/Packages"
fi
run "urls unknown channel" ko urls beta "$TMP/calaos.list"
echo "# nothing" >"$TMP/empty.list"
run "urls without deb line" ko urls stable "$TMP/empty.list"

# The repository's own control file goes through prepare unchanged but for Depends.
rm -rf "$TMP/real"
mkdir -p "$TMP/real/debian"
cp "$ROOT/calaos-meta/debian/control" "$ROOT/calaos-meta/debian/changelog" "$TMP/real/debian/"
mkdir -p "$TMP/real-index"
sed -n 's/^\(Depends:\)\? *\(calaos-[a-z0-9-]*\).*/\2/p' "$ROOT/calaos-meta/debian/control" |
    while read -r p; do stanza "$p" 1.0; done >"$TMP/real-index/all"
if run "real control" ok prepare stable 2026.11 "$TMP/real-index" "$TMP/real"; then
    diff <(sed '/^Depends:/,$d' "$ROOT/calaos-meta/debian/control") \
        <(sed '/^Depends:/,$d' "$TMP/real/debian/control") >/dev/null ||
        fail "real control: fields before Depends changed"
    [[ $(grep -c '(>= 1.0)' "$TMP/real/debian/control") -eq $(grep -c '^Depends: calaos-\|^ *calaos-' "$ROOT/calaos-meta/debian/control") ]] ||
        fail "real control: not every calaos-* entry is pinned"
    grep -qF "calaos-web-app (>= 1.0)" "$TMP/real/debian/control" || fail "real control: calaos-web-app not pinned"
fi

echo "$count cases, $failures failures"
((failures == 0))
