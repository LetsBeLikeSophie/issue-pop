# Anthropic API 키 이름 규칙 (비밀값 없음 — 이름/용도만 기록)

목적: Anthropic Console 사용량에서 **"어느 앱의 어느 기능에 비용이 많이 드는지"** 바로 보기.
앱이 여러 개로 늘어나도 같은 규칙으로 간다.

## 규칙

| 대상 | 규칙 | 예 |
|---|---|---|
| Console **워크스페이스** | 앱 하나에 하나 (앱 단위 비용/한도 분리) | `Issue Pop`, `Side Quest`, `Cortex`, `DailyCut` |
| Console **키 이름** | `<앱>-<기능>-<환경>` 소문자, 하이픈 | `issuepop-category-prod` |
| **환경변수 이름** | `ANTHROPIC_KEY_<기능>` (대문자, 앱별 서비스 환경파일에만) | `ANTHROPIC_KEY_CATEGORY` |

- 한 키는 **한 기능만** 쓴다. 기능을 새로 만들면 키도 새로 만든다(공용 키 재사용 금지).
- 앱끼리 키를 공유하지 않는다(특히 `/home/ubuntu/.env` 같은 공용 파일에 키를 두지 말 것 — 앱별 환경파일).
- 환경은 `prod`만 둔다(로컬 개발은 키 없이 폴백 경로로 돌거나 따로 `dev` 키).
- 워크스페이스마다 **월 사용 한도**를 건다(실수로 폭주해도 거기서 멈춤).

## 이슈팝 (워크스페이스: Issue Pop)

| Console 키 이름 | 환경변수 | 쓰는 곳 | 호출 규모 |
|---|---|---|---|
| `issuepop-category-prod` | `ANTHROPIC_KEY_CATEGORY` | `category.py` 이슈 카테고리 분류 | 하루 수천 회(제일 많음, 응답 20토큰) |
| `issuepop-audit-prod` | `ANTHROPIC_KEY_AUDIT` | `cluster_audit.py` 하루 1회 품질 감사 | 하루 수십 회 |
| `issuepop-wordofday-prod` | `ANTHROPIC_KEY_WORDOFDAY` | `word_of_day.py` 오늘의 단어 | 하루 1회 |
| `issuepop-translate-prod` | `ANTHROPIC_KEY_TRANSLATE` | `translate.py` 종목 뉴스 제목 번역 | 하루 100~300회 |

- 코드: `llm.complete(..., purpose="category")`가 `ANTHROPIC_KEY_CATEGORY`를 먼저 찾고, 없으면 예전 공용
  `ANTHROPIC_API_KEY`로 폴백한다(키를 하나씩 옮겨가도 안 깨짐). 번역은 예전 이름
  `ANTHROPIC_TRANSLATE_API_KEY`도 폴백으로 읽는다.
- 환경변수 위치(서버): `/etc/systemd/system/newstrend-api.service.d/env.conf` (git 아님).

## 다른 앱 (현재 상태 — 정리 대상)

- Side Quest: 공용 키 `…IAAA`(`/home/ubuntu/.env`)를 계속 씀. 개발 재개 때 `sidequest-<기능>-prod`로 새 키를 받아 교체.
- Cortex: 자기 키(`cortex-backend/.env`, `…LgAA`). 키 이름을 `cortex-<기능>-prod` 규칙으로 정리하면 좋음.
- DailyCut: 사용 안 함.

## 키 교체 순서 (이슈팝)

1. Console에서 `Issue Pop` 워크스페이스에 위 4개 키를 새로 만든다(이름 규칙대로).
2. 서버 `env.conf`에 `ANTHROPIC_KEY_CATEGORY=…` 등 4줄을 추가한다(파일 권한 600 유지). 값은 채팅/깃에 붙이지 않는다.
3. `sudo systemctl daemon-reload && sudo systemctl restart newstrend-api` (재시작 8~10분, 앱엔 점검 안내가 나감).
4. 몇 시간 뒤 Console 사용량에서 새 키 4개에 호출이 찍히는지, 예전 `…IAAA` 키의 이슈팝 호출이 0이 됐는지 확인.
5. 확인되면 `env.conf`의 예전 `ANTHROPIC_API_KEY`/`ANTHROPIC_TRANSLATE_API_KEY` 줄을 지운다(`…IAAA`는 Side Quest가 쓰니 폐기하지 않음).
