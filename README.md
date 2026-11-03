# tailscale-multi (`tsm`)

Be on several Tailscale tailnets **at the same time** on one Mac.

The Tailscale app can only have one tailnet active; "fast user switching" just flips between them.
`tsm` runs the open-source `tailscaled` once per tailnet, each as its own root launchd service with
its own `utun` interface, and keeps routing and DNS straight between them. Your normal internet traffic
is untouched (no exit nodes), it just goes out your usual connection.

```
$ tsm list
home         Running      100.101.5.7    tailabc123.ts.net     peers=3
work         Running      100.87.43.21   internal.example.com  peers=3
client       Running      100.64.0.4       client.tail.internal   peers=1
```

`ssh nas` reaches your home NAS, `git fetch` hits the client's private GitLab over its VPC route, and
`psql work-db` goes over the work tailnet, all without switching anything.

## Install

```sh
brew tap igorsigalovs/tailscale-multi https://github.com/igorsigalovs/tailscale-multi
brew trust igorsigalovs/tailscale-multi   # Homebrew ≥ 5 asks this once for third-party taps
brew install tsm
```

or without Homebrew's tap: `curl -fsSL https://raw.githubusercontent.com/igorsigalovs/tailscale-multi/main/install.sh | sh`
(needs `brew install tailscale` first).

**Quit and remove the Tailscale GUI app first.** It owns the same kernel resources and will fight the daemons.

## Use

```sh
tsm add home                                                   # Tailscale SaaS: opens a browser login
tsm add work --login-server https://headscale.example.com      # Headscale / self-hosted
tsm add client --login-server https://hs.client.com --auth-key tskey-...   # pre-auth key, no browser

tsm list                       # state of every tailnet
tsm status                     # every peer of every tailnet
tsm work ping db-1             # any tailscale command, per instance
tsm login work                 # re-authenticate after key expiry
tsm remove client              # leave one tailnet
tsm doctor                     # health check
tsm uninstall                  # remove everything tsm created
```

Each instance is a separate device named `<your-mac>-<name>` in that tailnet. Node keys expire per
the tailnet's policy; `tsm doctor` tells you when one needs `tsm login`.

## What it does under the hood

| Problem | What `tsm` does |
|---|---|
| Only one `tailscaled` state/socket | One service per tailnet: `/var/lib/tailscale-multi/<name>`, `/var/run/tailscale-multi/<name>.sock` |
| macOS `tailscaled` installs a single shared `100.64/10` route, so several daemons overwrite each other | A background job (every 2 min, and after every add/login/remove) installs a `/32` route per peer to the correct `utun` |
| MagicDNS (`100.100.100.100`) can only serve one tailnet | `--accept-dns` is off; the job writes every peer's MagicDNS name and short name into a managed block in `/etc/hosts` |
| Split DNS pushed by a tailnet (e.g. `internal.corp → 10.0.0.2`) would need the system resolver | The job renders each tailnet's split-DNS rules as `/etc/resolver/<domain>` files |
| Subnet routes | Accepted on every instance (`--accept-routes`), each lands on its own interface |

Everything it writes is marked and reversible: `tsm uninstall` removes the services, routes, the hosts
block and the resolver files it owns.

## Caveats

- **macOS only.** It leans on launchd, `/etc/resolver` and `utun`. A Linux port (systemd units,
  per-link DNS) is feasible but not written.
- **Replaces the GUI app.** No menu-bar icon, Taildrop or exit-node picker; everything is `tsm <name> ...`.
- **Address overlaps.** Every tailnet hands out addresses from `100.64.0.0/10`. If two of your tailnets
  give the *same* address to different machines, routing by IP is ambiguous. `tsm doctor` detects it;
  the fix is on the tailnet admin side (or use names, which are per-tailnet in `/etc/hosts`).
- **Overlapping subnet routes** (two tailnets advertising the same private CIDR) can't be told apart either.
- **Node expiry.** Tailscale SaaS keys expire after 180 days unless disabled per node; Headscale
  deployments have their own rules. Re-enroll with `tsm login <name>`.
- `sudo` is needed for anything that touches services, routes or `/etc`: `add`, `login`, `remove`,
  `sync`, `uninstall`.

## Development

```sh
brew install shellcheck bats-core
shellcheck bin/tsm
bats test
```

The sync logic is split into pure text functions (`render_hosts`, `parse_split_dns`) that the tests
exercise without root or a running tailscale.

## License

MIT
