#!/usr/bin/env bats
# Unit tests for the pure-text parts of tsm (no root, no tailscale needed).

setup() {
  export TSM_SOURCED=1
  export TSM_TAILSCALED=/bin/true TSM_TAILSCALE=/bin/true
  # shellcheck disable=SC1091
  source "$BATS_TEST_DIRNAME/../bin/tsm"
  TMP=$(mktemp -d)
}

teardown() { rm -rf "$TMP"; }

@test "render_hosts replaces an existing managed block and keeps the rest" {
  cat >"$TMP/hosts" <<EOF
127.0.0.1 localhost
$HOSTS_BEGIN
100.1.1.1 old.example old
$HOSTS_END
::1 localhost
EOF
  table=$'100.64.0.4       mac-a.ts.net mac-a utun7\n100.64.0.1       gw.ts.net gw utun7'
  run render_hosts "$TMP/hosts" "$table"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "127.0.0.1 localhost" ]
  [ "${lines[1]}" = "::1 localhost" ]
  [ "${lines[2]}" = "$HOSTS_BEGIN" ]
  [ "${lines[3]}" = "100.64.0.4 mac-a.ts.net mac-a" ]
  [ "${lines[4]}" = "100.64.0.1 gw.ts.net gw" ]
  [ "${lines[5]}" = "$HOSTS_END" ]
  [[ "$output" != *"old.example"* ]]
}

@test "render_hosts adds a block when none exists" {
  printf '127.0.0.1 localhost\n' >"$TMP/hosts"
  run render_hosts "$TMP/hosts" ""
  [ "${lines[0]}" = "127.0.0.1 localhost" ]
  [ "${lines[1]}" = "$HOSTS_BEGIN" ]
  [ "${lines[2]}" = "$HOSTS_END" ]
}

@test "parse_split_dns extracts domain -> nameserver pairs from dns status output" {
  input=$'=== MagicDNS configuration ===\n\nSplit DNS Routes:\n  - code.example.com        -> 10.40.0.2\n  - ts.net.                 -> 199.247.155.53\n  - ts.net.                 -> 2620:111:8007::53\n\nSearch Domains:\n  - foo.ts.net\n'
  printf '%s' "$input" >"$TMP/in"
  run parse_split_dns <"$TMP/in"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "code.example.com 10.40.0.2" ]
  [ "${lines[1]}" = "ts.net 199.247.155.53" ]
  [ "${lines[2]}" = "ts.net 2620:111:8007::53" ]
  [ "${#lines[@]}" -eq 3 ]
}

@test "parse_split_dns ignores output without a split section" {
  printf 'MagicDNS: enabled\n\nSearch Domains:\n  - a.ts.net\n' >"$TMP/in"
  run parse_split_dns <"$TMP/in"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "help lists every command" {
  run cmd_help
  for c in "tsm list" "tsm status" "tsm add" "tsm login" "tsm remove" "tsm sync" "tsm doctor" "tsm uninstall"; do
    [[ "$output" == *"$c"* ]]
  done
}

@test "instance names are validated" {
  run cmd_add "Bad Name"
  [ "$status" -ne 0 ]
  [[ "$output" == *"lowercase"* ]]
}
