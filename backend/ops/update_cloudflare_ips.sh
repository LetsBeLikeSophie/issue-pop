#!/bin/bash
# Cloudflare IP 대역 허용 목록을 갱신해서 nginx의 api.issue-pop.com 서버 블록이 Cloudflare에서 온 요청만 받게 함 (2026-10-27).
# - 목록: https://www.cloudflare.com/ips-v4 , ips-v6 → /etc/nginx/cloudflare-allow.conf (allow ...; + 로컬 + deny all;)
# - 검증(CIDR 형식·비어 있지 않음) → nginx -t 통과해야만 교체·reload, 실패하면 이전 파일로 되돌림.
# - 크론: 매월 1일 19:20 UTC. 로그: /home/ubuntu/backups/cloudflare-ips.log
set -uo pipefail

OUT=/etc/nginx/cloudflare-allow.conf
LOG=/home/ubuntu/backups/cloudflare-ips.log
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

log() { echo "$(date -Is) $1" >> "$LOG"; }

curl -fsS --max-time 30 https://www.cloudflare.com/ips-v4 -o "$TMP/v4" || { log "FAIL v4 다운로드"; exit 1; }
curl -fsS --max-time 30 https://www.cloudflare.com/ips-v6 -o "$TMP/v6" || { log "FAIL v6 다운로드"; exit 1; }

# 줄 사이에 개행을 보장해서 합침(Cloudflare 파일은 마지막 줄에 개행이 없어서, 그냥 cat하면 v4 마지막 줄과 v6 첫 줄이 한 줄로 붙었음)
{ cat "$TMP/v4"; echo; cat "$TMP/v6"; echo; } | tr -d '' | grep -v '^[[:space:]]*$' > "$TMP/all"

# 형식 검증: 모든 줄이 IPv4 CIDR 또는 IPv6 CIDR이어야 함, 최소 개수
V4='^[0-9]{1,3}(\.[0-9]{1,3}){3}/[0-9]{1,2}$'
V6='^[0-9a-fA-F:]+/[0-9]{1,3}$'
if grep -qEv "$V4|$V6" "$TMP/all"; then log "FAIL 형식이 이상한 줄이 있음"; exit 1; fi
if [ "$(wc -l < "$TMP/all")" -lt 10 ]; then log "FAIL 목록이 너무 짧음"; exit 1; fi

{
  echo "# Cloudflare IP 대역 (자동 생성 $(date -Is)) — update_cloudflare_ips.sh"
  while read -r cidr; do echo "allow $cidr;"; done < "$TMP/all"
  echo "allow 127.0.0.1;"
  echo "allow ::1;"
  echo "deny all;"
} > "$TMP/new.conf"

[ -f "$OUT" ] && cp -a "$OUT" "$TMP/old.conf"
cp "$TMP/new.conf" "$OUT"
if nginx -t >/dev/null 2>&1; then
  systemctl reload nginx && log "ok $(wc -l < "$TMP/all")개 대역" || log "FAIL reload"
else
  [ -f "$TMP/old.conf" ] && cp "$TMP/old.conf" "$OUT"
  log "FAIL nginx -t 실패, 이전 목록으로 되돌림"
  exit 1
fi
