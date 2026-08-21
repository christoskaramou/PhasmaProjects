-- Where internet games meet, and the key that proves it is the right server.
--
-- Fill both lines in after running `relay/deploy.sh user@your.server` — it prints them. The pin
-- is the SHA-256 of the relay's public key, base64: the game refuses to speak to anything whose
-- key does not hash to exactly this, which is why no certificate authority is involved and why
-- swapping the relay's certificate locks out old builds on purpose.
--
-- Left blank, the Online rows say "no relay configured" instead of failing at connect time.
-- LAN play does not use any of this.
return {
    host = "",
    port = 27600,
    pin = "",
}
