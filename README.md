# issue-pop

여러 매체의 RSS를 모아 "오늘 어떤 이슈가 많이 보도됐는지" 클러스터링해서 보여주는 뉴스 트렌드 앱.

![Python](https://img.shields.io/badge/Python-3776AB?style=flat-square&logo=python&logoColor=white)
![FastAPI](https://img.shields.io/badge/FastAPI-009688?style=flat-square&logo=fastapi&logoColor=white)
![Flutter](https://img.shields.io/badge/Flutter-02569B?style=flat-square&logo=flutter&logoColor=white)
![SQLite](https://img.shields.io/badge/SQLite-003B57?style=flat-square&logo=sqlite&logoColor=white)

## 구성

- **`backend/`** — RSS 크롤링, 이슈 클러스터링, FastAPI 서버 (Python)
- **`app/`** — 모바일 클라이언트 (Flutter)

## 핵심 로직

- 한국어 문장 임베딩(`ko-sroberta-multitask`) + 코사인 유사도 + Agglomerative Clustering(complete-linkage)으로, 매체마다 표현이 달라도 같은 이슈를 하나로 묶음
- kiwipiepy 형태소 분석 기반 대표 키워드 추출
- 규칙 기반 카테고리 분류 (정치·경제·사회·국제·스포츠·연예·IT과학·문화·기타)
- FastAPI + SQLModel/SQLite — 서버가 30분마다 백그라운드로 재수집·재클러스터링해서 캐시를 채우고, API 요청은 캐시만 읽어서 가볍게 응답
- Claude(Haiku)를 이용한 두 가지 LLM 기능: 오늘 뉴스에서 뽑은 어려운 단어를 사전 뜻풀이와 함께 골라주는 "오늘의 단어", 하루 한 번 클러스터링 결과 품질(키워드 잘림·오분류·카테고리 오류)을 검증해서 규칙 파일 개선에 반영하는 클러스터 감사

## 실행

```bash
cd backend
pip install -r requirements.txt
python3 pipeline.py --live      # 클러스터링 파이프라인 단독 실행
uvicorn api:app --reload        # API 서버
```

```bash
cd app
flutter run -d chrome
```

## 더 자세한 내용

검증 과정, 튜닝 히스토리, 발견한 버그와 원인은 [`backend/README.md`](backend/README.md)에 정리되어 있습니다.
