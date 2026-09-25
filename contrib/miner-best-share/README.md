# miner-best-share

How close has each of your miners come to finding a block?

`miner-best-share` is a small poller that runs next to the DATUM Gateway. Every 5 minutes it

1. asks the gateway for its stratum client list — each client's **Auth Username** becomes the miner's
   name and its address is where the miner is polled;
2. reads every miner's cgminer/sgminer API (`summary` on TCP 4028) for **Best Share** — the highest
   share difficulty the miner has produced since its mining process started — and its 5-minute hashrate;
3. writes a plain-text report that the gateway's **Best** page (`/best`) displays:

```
Bitcoin — best share difficulty per miner per day   (last poll 2026-09-22 13:53 MDT)

Network difficulty to find a block: 132,757,073,449,488  (132.76 T)
A share at that difficulty would have been a block.  '% of block' = best share / network difficulty;  '1 in N' = network difficulty / best share.

HASHRATE AND ODDS OF FINDING A BLOCK   (hashrate = average of 5-min readings over the last 60 min)
  miner              hashrate   per day        per week       per month      per year
  worker1           2.17 TH/s   1 in 3.05 M    1 in 435.34 k  1 in 100.12 k  1 in 8.34 k
  worker2          54.39 TH/s   1 in 121.33 k  1 in 17.33 k   1 in 3.99 k    1 in 333
  ALL MINERS       56.56 TH/s   1 in 116.69 k  1 in 16.67 k   1 in 3.83 k    1 in 320

CLOSEST EVER
  worker1            87.69 M     0.000066 %   1 in 1.51 M    on 2026-09-22 13:08
  worker2           185.32 M      0.00014 %   1 in 716.36 k  on 2026-09-22 13:14

BY DAY
  date        miner          best share     % of block   1 in N of a block
  2026-09-22  worker1           87.69 M     0.000066 %   1 in 1.51 M    (13:08)
  2026-09-22  worker2          185.32 M      0.00014 %   1 in 716.36 k  (13:14)
```

* **% of block / 1 in N** — the best share relative to the network difficulty (a share at the network
  difficulty *is* a block). A "how far away" figure for one lucky share, not a probability.
* **per day / week / month / year** — probability of finding at least one block in that period at the
  miner's 60-minute average hashrate and the current difficulty (Poisson, `1 - e^-λ`,
  `λ = hashrate × seconds / (difficulty × 2^32)`). Once a block or more is *expected* in the period the
  column shows the expected count instead (`~1.5 blocks`).
* **BY DAY** records the best share that was newly observed on that (local) day. A miner's Best Share
  resets when it restarts; a value that has not changed since the previous poll is not counted again,
  and a drop is treated as a restart.

Miners that expose no cgminer API (e.g. NerdMiner-class devices) show up as unreachable.

## Install

Requirements: Python 3.9+ (`zoneinfo`), a DATUM Gateway with `api.admin_password` set (the client list
requires it), and miners whose API port 4028 is reachable from the gateway host.

```
sudo ./install.sh                                    # copies the script, units, and an example config
sudo cp miner-best-share.json.example /etc/miner-best-share.json   # then edit: title, timezone, difficulty source
sudo systemctl enable --now miner-best-share.timer
sudo miner-best-share report
```

The report lands in `/var/lib/miner-best-share/report.txt`, which is the default `api.best_report_path`
of this DATUM fork, so `/best` on the dashboard shows it immediately. `daily.csv` sits next to it.

### Config reference (`/etc/miner-best-share.json`)

| key | default | meaning |
|---|---|---|
| `title` | `Best shares` | first line of the report / page title |
| `timezone` | `UTC` | day boundaries for BY DAY (e.g. `America/Denver`) |
| `datum_config` | `/etc/datum/datum_gateway_config.json` | read `api.admin_password` and `api.listen_port` from here |
| `gateway_url` / `admin_password` | derived | set these instead if the DATUM config is elsewhere or unreadable |
| `discover` | `true` | discover miners from the gateway's client list |
| `miners` | `[]` | extra static miners: `{"name": "...", "host": "...", "port": 4028}` (e.g. behind NAT) |
| `miner_api_port` / `miner_api_ports` | `4028` / `[4028, 4029]` | cgminer API ports to try, in order (iBeLink firmware listens on 4029); the port that answers is remembered per miner |
| `difficulty_cmd` | `["bitcoin-cli", "getdifficulty"]` | command printing the network difficulty |
| `difficulty_key` | `""` | if the command prints JSON, the key to read |
| `difficulty_divisor` | `1` | divide the node's value to get share-difficulty units (see BLAKE2b below) |
| `mempool_api` | `""` | optional fallback such as `https://mempool.space/api` |
| `report_days` | `30` | days shown in BY DAY |
| `idle_hashrate_hps` | `1e9` | below this 60-min average a miner is shown as `0 H/s` with no odds (a stopped miner's API keeps answering) |
| `stale_days` | `3` | a miner that has left the gateway and not answered its API for this long drops out of the live tables (its BY DAY history stays); `miner-best-share forget NAME` removes one entirely |
| `state_dir` | `/var/lib/miner-best-share` | state.json, report.txt, daily.csv |
| `www_dir` | `""` | also write `index.html` + `report.txt` here for a plain web server (see below) |

Miner names: the stratum username as sent by the miner. For `payoutaddress.worker` style usernames
(pool_pass_full_users), only the `worker` part is used. A miner keeps the name it was first recorded
under: if the same address later shows up with another username (a backup pool slot with a different
worker name, for instance) that username is stored as an alias instead of creating a second miner.
To rename one on purpose use `miner-best-share rename OLD NEW`, or pin names per address with
`"names": {"<address>": "<name>"}` in the config.

### BLAKE2b (Bitcoin Knots 29.4.x hard fork)

`getdifficulty` was removed there and `getblockchaininfo` reports `difficulty_blake2b`, which is
*hashes per block* (`2^256 / target`) rather than a share-difficulty. Use
`miner-best-share-blake2b.json.example`: it reads that key and divides by 2^32 so that the miners'
Best Share values (standard diff-1 = 2^32 hashes on Sia-stratum firmware too) compare correctly.

### Stock DATUM Gateway (no `/best` page)

The poller also works against an unmodified gateway: it falls back to scraping the `/clients` page
for the miner list. To view the report, set `www_dir` and serve that directory from nginx next to the
dashboard proxy, e.g.

```nginx
location = /best { return 301 /best/; }
location /best/ { alias /var/www/miner-best-share/; index index.html; }
# optional: inject a "Best" button into the stock dashboard's menu
location / {
    proxy_pass http://127.0.0.1:7152;
    proxy_set_header Accept-Encoding "";
    sub_filter '>Coinbaser</a>' '>Coinbaser</a> <a href="/best/">Best</a>';
    sub_filter_once on;
}
```

## Files

* `miner-best-share` — the poller/report script
* `miner-best-share.json.example` — Bitcoin (SHA256d) config
* `miner-best-share-blake2b.json.example` — BLAKE2b fork config
* `miner-best-share.service`, `miner-best-share.timer` — systemd units (every 5 minutes, as root)
* `install.sh` — copies the above into place
