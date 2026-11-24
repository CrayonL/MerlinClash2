#!/usr/bin/env bash
# Run against a disposable copy of the router paths. No network or router is needed.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
ks="$tmp/koolshare"
out="$tmp/upload"
mkdir -p "$ks/bin" "$ks/scripts" "$ks/merlinclash/yaml_bak" "$out" "$tmp/bin"
for script in clash_online_yaml clash_regular_update clash_online_yaml4 clash_updateyamlsel clash_downyamlsel clash_config_name; do
    src="$root/merlinclash/scripts/$script.sh"
    [ -f "$src" ] || continue
    sed -e 's/\r$//' -e "s|/koolshare|$ks|g" -e "s|/tmp/upload|$out|g" "$src" > "$ks/scripts/$script.sh"
done
export KS_TEST="$ks" TEST_OUT="$out" PATH="$tmp/bin:$PATH"
cat > "$ks/scripts/base.sh" <<'SH'
dbus() {
    case "$1:$2" in
        get:merlinclash_uploadrename|get:merlinclash_uploadrename4|get:merlinclash_dc_uploadrename4|get:merlinclash_delyamlsel) printf '%s' "$TEST_NAME" ;;
        get:merlinclash_yamlsel) printf '%s' "$ACTIVE_NAME" ;;
        get:merlinclash_subscribeplan) echo all ;;
        get:merlinclash_links) echo test ;;
        get:merlinclash_enable) echo 0 ;;
    esac
}
http_response() { printf '%s\n' "$*" >> "$TEST_OUT/response"; }
SH
cat > "$ks/scripts/clash_base.sh" <<'SH'
. "$KS_TEST/scripts/base.sh"
get() { dbus get "$1"; }
decode_url_link() { printf 'https://example.invalid/sub'; }
echo_date() { echo "$@"; }
LOG_FILE="$TEST_OUT/merlinclash_log.txt"
SH
cat > "$ks/scripts/clash_download.sh" <<'SH'
download_by_mc2() { printf '%s\n' "$2" >> "$TEST_OUT/transfers"; exit 71; }
SH
printf '#!/bin/sh\nexit 0\n' > "$tmp/bin/sleep"
chmod +x "$tmp/bin/sleep"
for tool in curl wget subconverter; do
    printf '#!/bin/sh\necho unexpected-network-action >> "$TEST_OUT/transfers"\nexit 1\n' > "$tmp/bin/$tool"
    chmod +x "$tmp/bin/$tool"
done
ln -s "$tmp/bin/subconverter" "$ks/bin/subconverter"
export TEST_NAME='' ACTIVE_NAME=''
run() { bash -O expand_aliases "$ks/scripts/$1.sh" "${@:2}"; }
denied() {
    : > "$out/merlinclash_log.txt"
    : > "$out/merlinclash_regular.log"
    if run "$@" > "$out/console" 2>&1; then echo "unexpected success: $1 $3" >&2; exit 1; fi
    [ ! -s "$out/transfers" ] || { echo "empty name reached download: $1 $3" >&2; exit 1; }
    grep -q '添加配置名称' "$out"/merlinclash*.{log,txt} 2>/dev/null || grep -q '添加配置名称' "$out/console"
}
for TEST_NAME in '' '   ' '.yaml'; do
    denied clash_online_yaml request 2
    denied clash_online_yaml "$TEST_NAME" 1 https://example.invalid/sub
    denied clash_online_yaml4 request 16
    denied clash_online_yaml4 request 21
    denied clash_online_yaml4 "$TEST_NAME" 4 https://example.invalid/sub
    denied clash_downyamlsel request downyaml
done
denied clash_updateyamlsel request 0
denied clash_regular_update ignored ignored
dict="$ks/merlinclash/yaml_bak/subscription.txt"
[ ! -s "$dict" ]
printf '%s\n' '"name":".yaml","link":"https://example.invalid/bad","type":"1","use":"0"' \
    '"name":"Good.yaml","link":"https://example.invalid/good","type":"1","use":"0"' > "$dict"
run clash_regular_update > "$out/console" 2>&1
[ "$(cat "$out/transfers")" = "$out/Good.yaml" ]
grep -q '添加配置名称' "$out/merlinclash_regular.log"
echo 'PASS: blank names blocked, valid subscription after invalid record still dispatched.'
