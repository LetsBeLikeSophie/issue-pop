# 서버 운영 스크립트 (사본)

서버(Oracle, ubuntu 계정)의 `/home/ubuntu/`에 설치돼 있음. 여기 파일은 기록용 사본 — 고치면 서버에도 같이 반영해야 함.

| 파일 | 크론 | 하는 일 |
|---|---|---|
| `backup_issuepop_db.sh` | 매일 19:10 UTC (04:10 KST) — 등록됨 | DB를 안전하게 복사·검사·압축해 `/home/ubuntu/backups/daily/`에 7일치 보관 |
| `update_cloudflare_ips.sh` | **아직 미등록**(등록하려던 크론이 자동 승인에서 막힘) | Cloudflare IP 대역을 받아 `/etc/nginx/cloudflare-allow.conf`를 갱신하고 nginx reload. 실패하면 이전 목록으로 되돌림 |

`update_cloudflare_ips.sh`는 Cloudflare가 대역을 바꿀 때를 위한 것(드물게 바뀜). 등록하려면 서버에서 `crontab -e`로
`20 19 1 * * sudo /home/ubuntu/update_cloudflare_ips.sh`(매월 1일 19:20 UTC) 한 줄을 추가하거나, 가끔 수동으로 `sudo /home/ubuntu/update_cloudflare_ips.sh`를 실행하면 됨.

## Cloudflare 구성 (2026-10-27)
- Cloudflare SSL/TLS 모드: **Full (strict)** — 원서버 `api.issue-pop.com`의 Let's Encrypt 인증서(certbot, 자동 갱신)를 검증함.
- nginx `newstrend-api` 서버 블록: 80과 443(ssl)을 함께 받고, `include /etc/nginx/cloudflare-allow.conf;`로 Cloudflare 대역 + 로컬만 허용(나머지 403) → Cloudflare를 우회한 직접 접속과 `CF-Connecting-IP` 위조(속도 제한 우회)가 막힘.
- 80 포트로 리다이렉트를 걸지 말 것(Flexible로 되돌렸을 때 무한 리다이렉트).
- 되돌리기: `/home/ubuntu/backups/nginx/`의 `newstrend-api.pre-*` 백업 참고.
- 허용 목록 갱신 스크립트는 Cloudflare 파일(ips-v4)이 마지막 줄에 개행이 없다는 점을 처리함(안 그러면 v4 마지막 줄과 v6 첫 줄이 붙어 nginx 설정이 깨짐).
