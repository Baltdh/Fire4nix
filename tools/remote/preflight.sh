#!/bin/sh
# Read-only local checks. No tunnel, network request or report file is created.
LC_ALL=C
export LC_ALL
printf '%s\n' 'Fire4Nix remote preflight: no external access opened'
for tool in python3 cloudflared timeout; do
  if command -v "$tool" >/dev/null 2>&1; then
    printf '%s=available\n' "$tool"
  else
    printf '%s=missing\n' "$tool"
  fi
done
if command -v cloudflared >/dev/null 2>&1 && command -v timeout >/dev/null 2>&1; then
  if timeout 5 cloudflared tunnel --help 2>/dev/null | grep -q -- '--allowed-mail'; then
    printf '%s\n' 'cloudflared_email_auth=supported'
  else
    printf '%s\n' 'cloudflared_email_auth=not_confirmed'
  fi
fi
printf '%s\n' 'hub_direct_https=unsupported_by_reviewed_1.18_source' 'hardware_connection=not_tested'
