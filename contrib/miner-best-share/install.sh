#!/bin/sh
# Install miner-best-share next to a DATUM Gateway (run as root).
set -eu
cd "$(dirname "$0")"
install -m 755 miner-best-share /usr/local/bin/miner-best-share
install -m 644 miner-best-share.service miner-best-share.timer /etc/systemd/system/
install -d -m 755 /var/lib/miner-best-share
if [ ! -f /etc/miner-best-share.json ]; then
	install -m 644 miner-best-share.json.example /etc/miner-best-share.json
	echo "installed /etc/miner-best-share.json from the example -- edit title, timezone and difficulty source"
fi
systemctl daemon-reload
echo "now: systemctl enable --now miner-best-share.timer   (then: miner-best-share report)"
