#!/bin/sh
# Self-signed certificate for the relay, plus the pin the game checks against it.
#
# There is no CA here on purpose: the game pins THIS key rather than trusting the public PKI,
# so a certificate signed by anyone else — including a real CA — is refused. That is stronger
# than the usual browser trust model and it costs one line of config instead of a domain.
set -e
DAYS=${DAYS:-3650}
OUT=${OUT:-.}

openssl req -x509 -newkey rsa:2048 -sha256 -days "$DAYS" -nodes \
    -keyout "$OUT/key.pem" -out "$OUT/cert.pem" -subj "/CN=chess-relay" 2>/dev/null
chmod 600 "$OUT/key.pem"

PIN=$(openssl x509 -in "$OUT/cert.pem" -pubkey -noout |
      openssl pkey -pubin -outform der |
      openssl dgst -sha256 -binary |
      openssl base64)

echo "cert: $OUT/cert.pem   key: $OUT/key.pem   (valid $DAYS days)"
echo
echo "Put these two lines in Assets/Scripts/chess/relay_config.lua:"
echo "    host = \"<your.server.ip>\","
echo "    pin  = \"$PIN\","
