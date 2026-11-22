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
  for c in "tsm list" "tsm status" "tsm add" "tsm login" "tsm remove" "tsm sync" "tsm doctor" "tsm share" "tsm uninstall"; do
    [[ "$output" == *"$c"* ]]
  done
}

@test "instance names are validated" {
  run cmd_add "Bad Name"
  [ "$status" -ne 0 ]
  [[ "$output" == *"lowercase"* ]]
}

# --- tsm share: the proxy against a throw-away upstream on the loopback (no tailscale needed).

free_port() { python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])'; }

# An upstream like a local-only dev server: answers only when it is named 127.0.0.1:<its port>,
# echoes the method, and takes a write only from its own origin.
start_upstream() {
  UP=$(free_port)
  python3 - "$UP" >/dev/null 2>&1 <<'PY' &
import http.server, sys
port = int(sys.argv[1])
class H(http.server.BaseHTTPRequestHandler):
    def reply(self):
        if self.headers.get("Host") != "127.0.0.1:%d" % port:
            self.send_response(403); self.end_headers(); return
        if self.command == "POST" and self.headers.get("Origin") != "http://127.0.0.1:%d" % port:
            self.send_response(403); self.end_headers(); return
        if self.path == "/go":
            self.send_response(302); self.send_header("Location", "http://127.0.0.1:%d/there" % port)
            self.send_header("Content-Length", "0"); self.end_headers(); return
        body = ("%s %s" % (self.command, self.path)).encode()
        self.send_response(200); self.send_header("Content-Length", str(len(body))); self.end_headers()
        self.wfile.write(body)
    do_GET = do_POST = reply
    def log_message(self, *a): pass
http.server.HTTPServer(("127.0.0.1", port), H).serve_forever()
PY
  UP_PID=$!
  disown "$UP_PID"
  until port_answers 127.0.0.1 "$UP"; do kill -0 "$UP_PID"; done
}

share_setup() {
  export TSM_STATE_ROOT="$TMP/state" TSM_SHARE_ROOT="$TMP/shares" TSM_SHARE_BIND=127.0.0.1
  STATE_ROOT=$TSM_STATE_ROOT; SHARE_ROOT=$TSM_SHARE_ROOT
  mkdir -p "$STATE_ROOT/lab"
  start_upstream
  LISTEN=$(free_port)
}

share_teardown() { share_stop --all >/dev/null 2>&1 || true; kill "$UP_PID" 2>/dev/null || true; }

@test "share: the upstream refuses its tailnet name, and answers through the share" {
  share_setup
  run curl -s -o /dev/null -w '%{http_code}' -H 'Host: mac-lab.example:1' "http://127.0.0.1:$UP/"
  [ "$output" = "403" ]
  run share_start lab "$UP" --listen "$LISTEN"
  [ "$status" -eq 0 ]
  [[ "$output" == *"read-only"* ]]
  run curl -s -H 'Host: mac-lab.example:1' "http://127.0.0.1:$LISTEN/page?x=1"
  [ "$output" = "GET /page?x=1" ]
  share_teardown
}

@test "share: read-only refuses a write, and --write passes it with the local origin" {
  share_setup
  share_start lab "$UP" --listen "$LISTEN" >/dev/null
  run curl -s -o /dev/null -w '%{http_code}' -X POST -d a=1 "http://127.0.0.1:$LISTEN/save"
  [ "$output" = "405" ]
  share_stop lab "$LISTEN" >/dev/null
  share_start lab "$UP" --listen "$LISTEN" --write >/dev/null
  run curl -s -X POST -d a=1 -H "Origin: http://127.0.0.1:$LISTEN" "http://127.0.0.1:$LISTEN/save"
  [ "$output" = "POST /save" ]
  share_teardown
}

@test "share: a redirect to the local name comes back under the shared name" {
  share_setup
  share_start lab "$UP" --listen "$LISTEN" >/dev/null
  run curl -s -o /dev/null -w '%{redirect_url}' "http://127.0.0.1:$LISTEN/go"
  [ "$output" = "http://127.0.0.1:$LISTEN/there" ]
  share_teardown
}

@test "share: list shows a running share, stop ends it, a second start on the port is refused" {
  share_setup
  share_start lab "$UP" --listen "$LISTEN" >/dev/null
  run share_list
  [[ "$output" == *"lab"*"port $LISTEN"* ]]
  run share_start lab "$UP" --listen "$LISTEN"
  [ "$status" -ne 0 ]
  [[ "$output" == *"already shares"* ]]
  run share_stop lab "$LISTEN"
  [[ "$output" == *"stopped"* ]]
  run share_list
  [ "$output" = "no shares" ]
  share_teardown
}

@test "share: bad input is refused before anything starts" {
  share_setup
  run share_start lab notaport
  [ "$status" -ne 0 ]
  [[ "$output" == *"1 to 65535"* ]]
  run share_start nosuch "$UP"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no instance named"* ]]
  run share_start lab "$UP" --https --cert a --key b
  [ "$status" -ne 0 ]
  run share_list
  [ "$output" = "no shares" ]
  share_teardown
}

@test "share: --cert and --key serve the share over https" {
  share_setup
  openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj /CN=localhost \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" >/dev/null 2>&1
  run share_start lab "$UP" --listen "$LISTEN" --cert "$TMP/cert.pem" --key "$TMP/key.pem"
  [ "$status" -eq 0 ]
  [[ "$output" == *"https://"* ]]
  run curl -sk "https://127.0.0.1:$LISTEN/secure"
  [ "$output" = "GET /secure" ]
  share_teardown
}
