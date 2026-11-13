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
        printf 'Package: calaos-container\nVersion: 1.10.0-0~bookworm0\nArchitecture: amd64\n\n'
        printf 'Package: calaos-container\nVersion: 1.9.1-0~bookworm0\nArchitecture: amd64\n'
    } >"$dir/calaos-container.releases.amd64"
    : >"$dir/calaos-container.releases.arm64"
    printf 'Package: calaos-container\nVersion: 1.10.1~dev.1-0~bookworm0\nArchitecture: amd64\n' \
        >"$dir/calaos-container.pre-releases.amd64"
}

# expect_depends <name> <meta dir> <keyring> <container> <server> <web-app>
expect_depends()
{
    local name=$1 got want
    got=$(sed -n '/^Depends:/,$p' "$2/debian/control")
    shift 2
    want=$(printf 'Depends: calaos-keyring (>= %s),\n         calaos-container (>= %s),\n         calaos-server (>= %s),\n         calaos-web-app (>= %s),\n         ola,\n         chrony\n' "$@")
    [[ $got == "$want" ]] || fail "$name: Depends is"$'\n'"$got"
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
    2026.11-dev.1 1.2.3 2026.11.1a "2026.11 "; do
    fresh
    run "stable refuses '$v'" ko prepare stable "$v" "$TMP/case/index" "$TMP/case/meta" &&
        expect_contains "stable refuses '$v'" "$ERR" "not a stable Calaos OS version"
    cmp -s "$TMP/case/meta/debian/control" <(make_meta "$TMP/ref" && cat "$TMP/ref/debian/control") ||
        fail "stable refuses '$v': control modified"
done
for v in 2026.11 2026.11.1 2026.11~dev.01 2026.11~rc.1 2026.11.0~dev.1 \
    2026.11.01~dev.1 2026.11.1~dev.01 2026.11.1~dev 2026.11.1.1~dev.0 \
    2026.11~dev 2026.13~dev.1 2026.11~dev.1~dev.2; do
    fresh
    run "dev refuses '$v'" ko prepare dev "$v" "$TMP/case/index" "$TMP/case/meta" &&
        expect_contains "dev refuses '$v'" "$ERR" "not a dev Calaos OS version"
done
fresh
run "unknown channel refused" ko prepare beta 2026.11 "$TMP/case/index" "$TMP/case/meta"

# Accepted formats, and the version/tag outputs.
for spec in "stable 2026.11 2026.11 2026.11" "stable 2026.11.2 2026.11.2 2026.11.2" \
    "dev 2026.11~dev.0 2026.11~dev.0 2026.11-dev.0" "dev 2026.12-dev.3 2026.12~dev.3 2026.12-dev.3" \
    "dev 2026.11.1~dev.1 2026.11.1~dev.1 2026.11.1-dev.1" "dev 2026.11.2-dev.0 2026.11.2~dev.0 2026.11.2-dev.0"; do
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
    "dev 2026.11 2026.11~dev.4" "dev 2026.12~dev.1 2026.12~dev.1" "dev 2026.12~dev.2 2026.12~dev.1" \
    "dev 2026.11.1 2026.11.1~dev.0" "dev 2026.11.1~dev.0 2026.11~dev.5" "dev 2026.11.1~dev.2 2026.11.1~dev.1"; do
    read -r ch published v <<<"$spec"
    fresh
    stanza calaos "$published" >>"$TMP/case/index/pkgdebs.releases.all"
    run "$ch refuses $v after $published" ko prepare "$ch" "$v" "$TMP/case/index" "$TMP/case/meta" &&
        expect_contains "$ch refuses $v after $published" "$ERR" "is not greater than the published calaos $published"
done
for spec in "stable 2026.11 2026.11.1" "stable 2026.11~dev.3 2026.11" "stable 2026.12 2027.01" \
    "dev 2026.11 2026.12~dev.0" "dev 2026.12~dev.1 2026.12~dev.2" \
    "dev 2026.11 2026.11.1~dev.0" "stable 2026.11.1~dev.0 2026.11.1" "dev 2026.11.1~dev.0 2026.11.1~dev.1"; do
    read -r ch published v <<<"$spec"
    fresh
    stanza calaos "$published" >>"$TMP/case/index/pkgdebs.releases.all"
    run "$ch accepts $v after $published" ok prepare "$ch" "$v" "$TMP/case/index" "$TMP/case/meta"
done
# Without any published calaos, any well-formed version goes.
fresh
sed -i '/^Package: calaos$/,/^$/d' "$TMP/case/index/pkgdebs.releases.all"
run "first release accepted" ok prepare stable 2026.11 "$TMP/case/index" "$TMP/case/meta"

# Depends and changelog generated from the index. The index holds
# pre-releases too: a stable release must ignore them.
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
         calaos-container (>= 1.10.0-0~bookworm0),
         calaos-server (>= 4.10.0),
         calaos-web-app (>= 4.2.0),
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
  * calaos-container 1.10.0-0~bookworm0
  * calaos-server 4.10.0
  * calaos-web-app 4.2.0

 -- Calaos Team <team@calaos.fr>  Fri, 13 Nov 2026 12:00:00 +0000
EOF
    )
    [[ $(cat "$TMP/case/meta/debian/changelog") == "$want_changelog" ]] ||
        fail "depends: changelog is"$'\n'"$(cat "$TMP/case/meta/debian/changelog")"
    expect_contains "depends: notes" "$(cat "$TMP/case/notes.md")" "- calaos-server 4.10.0"
fi

# A dev release takes the pre-releases, but a stable release newer than every
# pre-release still wins.
fresh
stanza calaos-web-app 4.3.0 >>"$TMP/case/index/pkgdebs.releases.all"
if run "dev depends" ok prepare dev 2026.12~dev.0 "$TMP/case/index" "$TMP/case/meta" "$TMP/case/notes.md"; then
    expect_depends "dev depends" "$TMP/case/meta" 1.0.0 1.10.1~dev.1-0~bookworm0 4.11.0~dev.2 4.3.0
    expect_contains "dev depends: changelog" "$(cat "$TMP/case/meta/debian/changelog")" "  * calaos-server 4.11.0~dev.2"
fi

# An index directory filled by a dev fetch, then reused by a stable fetch:
# the pre-release files stay, and neither the Depends nor the published
# calaos may come from them. curl reads the file:// repositories offline.
rm -rf "$TMP/case"
make_meta "$TMP/case/meta"
make_index "$TMP/case/src"
stanza calaos 2026.12~dev.3 >>"$TMP/case/src/pkgdebs.pre-releases.all"
for f in "$TMP/case/src"/*; do
    IFS=. read -r repo comp arch <<<"${f##*/}"
    mkdir -p "$TMP/case/repo/$repo/dists/bookworm/$comp/binary-$arch"
    cp "$f" "$TMP/case/repo/$repo/dists/bookworm/$comp/binary-$arch/Packages"
done
for d in "$TMP/case/repo"/*; do
    for comp in releases pre-releases; do
        for arch in all amd64 arm64; do
            mkdir -p "$d/dists/bookworm/$comp/binary-$arch"
            touch "$d/dists/bookworm/$comp/binary-$arch/Packages"
        done
    done
    echo "deb file://$d bookworm releases"
done >"$TMP/case/calaos.list"
run "reused index: dev fetch" ok fetch dev "$TMP/case/calaos.list" "$TMP/case/index" &&
    run "reused index: stable fetch" ok fetch stable "$TMP/case/calaos.list" "$TMP/case/index"
[[ -s $TMP/case/index/pkgdebs.pre-releases.all ]] || fail "reused index: no pre-releases left by the dev fetch"
if run "reused index: stable" ok prepare stable 2026.11 "$TMP/case/index" "$TMP/case/meta"; then
    expect_depends "reused index: stable" "$TMP/case/meta" 1.0.0 1.10.0-0~bookworm0 4.10.0 4.2.0
    ! grep -q '~dev' "$TMP/case/meta/debian/control" "$TMP/case/meta/debian/changelog" ||
        fail "reused index: stable pins a pre-release"
fi
make_meta "$TMP/case/meta"
run "reused index: dev sees the published dev calaos" ko prepare dev 2026.12~dev.3 "$TMP/case/index" "$TMP/case/meta" &&
    expect_contains "reused index: dev" "$ERR" "not greater than the published calaos 2026.12~dev.3"

# A component published only as a pre-release is missing for stable.
fresh
sed -i '/^Package: calaos-web-app$/,/^$/d' "$TMP/case/index/pkgdebs.releases.all"
run "stable without a stable component" ko prepare stable 2026.11 "$TMP/case/index" "$TMP/case/meta" &&
    expect_contains "stable without a stable component" "$ERR" "not published in the stable channel: calaos-web-app"
make_meta "$TMP/case/meta"
run "dev with a pre-release component" ok prepare dev 2026.12~dev.0 "$TMP/case/index" "$TMP/case/meta"

# A version on one arch only is not required on the others: the pin is the
# lowest of the per-arch highest versions. The published calaos is the highest.
fresh
rm "$TMP/case/index/pkgdebs.releases.all"
{
    stanza calaos-keyring 1.0.0
    stanza calaos-container 1.9.1
    stanza calaos-server 4.10.0
    stanza calaos-web-app 4.2.0
    stanza calaos 2026.10
} >"$TMP/case/index/pkgdebs.releases.amd64"
{
    stanza calaos-container 1.9.0
    stanza calaos-server 4.9.0
    stanza calaos-server 4.8.0
    stanza calaos 2026.11
} >"$TMP/case/index/pkgdebs.releases.arm64"
rm "$TMP/case/index"/calaos-container.*
if run "per-arch pin" ok prepare stable 2026.12 "$TMP/case/index" "$TMP/case/meta"; then
    expect_depends "per-arch pin" "$TMP/case/meta" 1.0.0 1.9.0 4.9.0 4.2.0
fi
make_meta "$TMP/case/meta"
run "per-arch published" ko prepare stable 2026.11 "$TMP/case/index" "$TMP/case/meta" &&
    expect_contains "per-arch published" "$ERR" "not greater than the published calaos 2026.11"

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
fresh
rm -f "$TMP/case/index"/*.releases.*
run "no index of the channel" ko prepare stable 2026.11 "$TMP/case/index" "$TMP/case/meta" &&
    expect_contains "no index of the channel" "$ERR" "no apt index of the stable channel"

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
    while read -r p; do stanza "$p" 1.0; done >"$TMP/real-index/pkgdebs.releases.all"
if run "real control" ok prepare stable 2026.11 "$TMP/real-index" "$TMP/real"; then
    diff <(sed '/^Depends:/,$d' "$ROOT/calaos-meta/debian/control") \
        <(sed '/^Depends:/,$d' "$TMP/real/debian/control") >/dev/null ||
        fail "real control: fields before Depends changed"
    [[ $(grep -c '(>= 1.0)' "$TMP/real/debian/control") -eq $(grep -c '^Depends: calaos-\|^ *calaos-' "$ROOT/calaos-meta/debian/control") ]] ||
        fail "real control: not every calaos-* entry is pinned"
    grep -qF "calaos-web-app (>= 1.0)" "$TMP/real/debian/control" || fail "real control: calaos-web-app not pinned"
fi

# Computed version: next <channel> <month> <published versions...>.
# Non calendar versions (the 1.1.4 of the old scheme) are ignored.
for spec in \
    "stable|2026.11|2026.11" \
    "stable|2026.11|2026.11|1.1.4" \
    "stable|2026.11|2026.11|2026.10 2026.10.3" \
    "stable|2026.11|2026.11.1|2026.11" \
    "stable|2026.11|2026.11.3|2026.11 2026.11.1 2026.11.2 2026.11~dev.4" \
    "stable|2026.11|2026.11.2|2026.11.1 2026.11" \
    "stable|2026.12|2026.12|2026.11.2" \
    "stable|2027.01|2027.01|2026.12 2026.12.1" \
    "stable|2026.11|2026.11|2026.11~dev.1 2026.11.1~dev.2" \
    "dev|2026.11|2026.11~dev.1" \
    "dev|2026.11|2026.11~dev.1|2026.10 1.1.4" \
    "dev|2026.11|2026.11~dev.2|2026.11~dev.1" \
    "dev|2026.11|2026.11~dev.11|2026.11~dev.10 2026.11~dev.9" \
    "dev|2026.11|2026.11.1~dev.1|2026.11" \
    "dev|2026.11|2026.11.2~dev.1|2026.11 2026.11.1 2026.11~dev.7" \
    "dev|2026.11|2026.11.1~dev.4|2026.11 2026.11.1~dev.3 2026.11.1~dev.1" \
    "dev|2026.12|2026.12~dev.1|2026.11.1 2026.11.2~dev.5" \
    "dev|2027.01|2027.01~dev.3|2026.12 2027.01~dev.2 2027.01~dev.1"; do
    IFS='|' read -r ch month want published <<<"$spec"
    # shellcheck disable=SC2086
    if run "next $ch $month [$published]" ok next "$ch" "$month" $published; then
        [[ $OUT == "$want" ]] || fail "next $ch $month [$published]: got '$OUT', want '$want'"
    fi
done
run "next refuses a bad month" ko next stable 2026.13
run "next refuses a bad channel" ko next beta 2026.11

# prepare with an empty version computes it from the index and the month.
export CALAOS_OS_RELEASE_MONTH=2026.11
fresh
if run "auto stable, nothing of the month" ok prepare stable "" "$TMP/case/index" "$TMP/case/meta"; then
    [[ $OUT == "version=2026.11"$'\n'"tag_version=2026.11" ]] || fail "auto stable: output '$OUT'"
    expect_contains "auto stable" "$ERR" "computed version 2026.11"
    head -1 "$TMP/case/meta/debian/changelog" | grep -qxF "calaos (2026.11) bookworm; urgency=medium" ||
        fail "auto stable: changelog header"
fi
fresh
stanza calaos 2026.11 >>"$TMP/case/index/pkgdebs.releases.all"
run "auto stable, second of the month" ok prepare stable "" "$TMP/case/index" "$TMP/case/meta" &&
    [[ $OUT == "version=2026.11.1"$'\n'"tag_version=2026.11.1" ]] || fail "auto stable .1: output '$OUT'"
fresh
stanza calaos 2026.10.2 >>"$TMP/case/index/pkgdebs.releases.all"
run "auto stable, new month" ok prepare stable "" "$TMP/case/index" "$TMP/case/meta" &&
    [[ $OUT == "version=2026.11"$'\n'"tag_version=2026.11" ]] || fail "auto stable new month: output '$OUT'"
fresh
run "auto dev, first" ok prepare dev "" "$TMP/case/index" "$TMP/case/meta" &&
    [[ $OUT == "version=2026.11~dev.1"$'\n'"tag_version=2026.11-dev.1" ]] || fail "auto dev first: output '$OUT'"
fresh
stanza calaos 2026.11~dev.1 >>"$TMP/case/index/pkgdebs.pre-releases.all"
run "auto dev, next dev" ok prepare dev "" "$TMP/case/index" "$TMP/case/meta" &&
    [[ $OUT == "version=2026.11~dev.2"$'\n'"tag_version=2026.11-dev.2" ]] || fail "auto dev next: output '$OUT'"
fresh
stanza calaos 2026.11 >>"$TMP/case/index/pkgdebs.releases.all"
stanza calaos 2026.11~dev.3 >>"$TMP/case/index/pkgdebs.pre-releases.all"
run "auto dev, after the stable of the month" ok prepare dev "" "$TMP/case/index" "$TMP/case/meta" &&
    [[ $OUT == "version=2026.11.1~dev.1"$'\n'"tag_version=2026.11.1-dev.1" ]] || fail "auto dev after stable: output '$OUT'"
fresh
stanza calaos 2026.11 >>"$TMP/case/index/pkgdebs.releases.all"
stanza calaos 2026.11~dev.3 >>"$TMP/case/index/pkgdebs.pre-releases.all"
stanza calaos 2026.11.1~dev.1 >>"$TMP/case/index/pkgdebs.pre-releases.all"
run "auto dev, second dev after the stable" ok prepare dev "" "$TMP/case/index" "$TMP/case/meta" &&
    [[ $OUT == "version=2026.11.1~dev.2"$'\n'"tag_version=2026.11.1-dev.2" ]] || fail "auto dev second after stable: output '$OUT'"
fresh
stanza calaos 2026.11 >>"$TMP/case/index/pkgdebs.releases.all"
stanza calaos 2026.11.1 >>"$TMP/case/index/pkgdebs.releases.all"
stanza calaos 2026.11.2~dev.4 >>"$TMP/case/index/pkgdebs.pre-releases.all"
run "auto dev, dev above two stables" ok prepare dev "" "$TMP/case/index" "$TMP/case/meta" &&
    [[ $OUT == "version=2026.11.2~dev.5"$'\n'"tag_version=2026.11.2-dev.5" ]] || fail "auto dev above stables: output '$OUT'"
fresh
stanza calaos 2026.11 >>"$TMP/case/index/pkgdebs.releases.all"
stanza calaos 2026.11.1~dev.1 >>"$TMP/case/index/pkgdebs.pre-releases.all"
stanza calaos 2026.11.1~dev.2 >>"$TMP/case/index/pkgdebs.pre-releases.all"
stanza calaos 2026.11.1 >>"$TMP/case/index/pkgdebs.releases.all"
run "auto dev, stable newer than its devs" ok prepare dev "" "$TMP/case/index" "$TMP/case/meta" &&
    [[ $OUT == "version=2026.11.2~dev.1"$'\n'"tag_version=2026.11.2-dev.1" ]] || fail "auto dev after newer stable: output '$OUT'"
# A stable run does not read pre-releases, a dev run reads the stables.
fresh
stanza calaos 2026.11~dev.3 >>"$TMP/case/index/pkgdebs.pre-releases.all"
run "auto stable ignores pre-releases" ok prepare stable "" "$TMP/case/index" "$TMP/case/meta" &&
    [[ $OUT == "version=2026.11"$'\n'"tag_version=2026.11" ]] || fail "auto stable ignoring dev: output '$OUT'"
# A published version from a later month than the clock still stops the release.
fresh
stanza calaos 2026.12 >>"$TMP/case/index/pkgdebs.releases.all"
run "auto refuses when behind the index" ko prepare stable "" "$TMP/case/index" "$TMP/case/meta" &&
    expect_contains "auto behind" "$ERR" "is not greater than the published calaos 2026.12"
# A given version wins over the computation.
fresh
stanza calaos 2026.11 >>"$TMP/case/index/pkgdebs.releases.all"
run "given version wins" ok prepare stable 2026.12 "$TMP/case/index" "$TMP/case/meta" &&
    [[ $OUT == "version=2026.12"$'\n'"tag_version=2026.12" ]] || fail "given version: output '$OUT'"
[[ $ERR != *"computed version"* ]] || fail "given version: computed anyway"
fresh
stanza calaos 2026.11 >>"$TMP/case/index/pkgdebs.releases.all"
run "given version still checked" ko prepare stable 2026.11 "$TMP/case/index" "$TMP/case/meta"
unset CALAOS_OS_RELEASE_MONTH

echo "$count cases, $failures failures"
((failures == 0))
