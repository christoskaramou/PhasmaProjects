#!/bin/sh
# One command to put the relay on a box you own:  ./deploy.sh root@your.server
#
# Idempotent: re-running it updates relay.py and restarts the service, and it keeps the existing
# certificate — regenerating one would change the pin and lock out every copy of the game that
# has the old one baked in.
set -e
TARGET=$1
PORT=${PORT:-27600}
if [ -z "$TARGET" ]; then
    echo "usage: ./deploy.sh user@host   (needs ssh access and sudo/root on the far end)"
    exit 2
fi

DIR=$(dirname "$0")
echo "copying to $TARGET ..."
scp "$DIR/relay.py" "$DIR/make_cert.sh" "$DIR/chess-relay.service" "$TARGET:/tmp/"

ssh "$TARGET" "sh -s" <<EOF
set -e
id chessrelay >/dev/null 2>&1 || useradd --system --no-create-home --shell /usr/sbin/nologin chessrelay
mkdir -p /opt/chess-relay
mv /tmp/relay.py /tmp/make_cert.sh /opt/chess-relay/
mv /tmp/chess-relay.service /etc/systemd/system/chess-relay.service
chmod +x /opt/chess-relay/make_cert.sh

if [ ! -f /opt/chess-relay/cert.pem ]; then
    (cd /opt/chess-relay && OUT=/opt/chess-relay sh make_cert.sh)
fi
chown -R chessrelay:chessrelay /opt/chess-relay
chmod 600 /opt/chess-relay/key.pem

systemctl daemon-reload
systemctl enable --now chess-relay
systemctl restart chess-relay
sleep 1
systemctl is-active chess-relay

command -v ufw >/dev/null 2>&1 && ufw allow $PORT/tcp >/dev/null 2>&1 || true

echo
echo "pin for Assets/Scripts/chess/relay_config.lua:"
openssl x509 -in /opt/chess-relay/cert.pem -pubkey -noout |
    openssl pkey -pubin -outform der |
    openssl dgst -sha256 -binary |
    openssl base64
EOF

echo
echo "Done. Open TCP $PORT in the provider's firewall too if it has one of its own."
