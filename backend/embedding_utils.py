# -*- coding: utf-8 -*-
"""
문장 임베딩 공용 유틸 (2026-08-24 추가).

clustering.py(이슈 클러스터링)와 meta_cluster.py(슈퍼그룹 재클러스터링)가
같은 임베딩 모델을 공유해서 쓰도록 뺐어요.

배경: 원래는 kiwipiepy 명사 추출 + 문자 n-gram TF-IDF로 유사도를 쟀는데,
"매체마다 표현이 완전히 다른 같은 이슈"를 놓치는 경우가 있었어요(예:
"이소희·백하나, 배드민턴 세계선수권 여자복식 31년 만에 우승" vs
"백하나-이소희, 배드민턴 女복식 세계선수권 31년 만의 金" — 겹치는 글자가
거의 없음). 문장 임베딩(의미 벡터)으로 바꾸면 표현이 달라도 뜻이 같으면
가깝게 잡힘.

**모델 선택 과정**: 처음엔 범용 다국어 모델(paraphrase-multilingual-
MiniLM-L12-v2)을 실측했는데, 매체별 "문체"(예: 머니투데이 스포츠
캡션체, 한겨레 칼럼체)를 지나치게 비슷하다고 판단해서 완전히 다른
주제의 기사들을 섞어버리는 문제가 있었음(threshold를 0.9까지 올려도
안 없어짐). 한국어 STS(문장 유사도) 전용으로 학습된 `jhgan/ko-sroberta-
multitask`로 바꾸니 이 문제가 훨씬 줄었고, 샘플 픽스처에서도 char
n-gram 버전보다 더 정확했음(연금개혁 공청회 기사까지 국민연금 이슈에
정확히 포함시킴). 자세한 실측 과정은 backend/README.md 참고.

**성능 참고**: 461건 인코딩에 로컬 CPU 기준 약 20~50초 걸림(모델 크기에
따라 다름). 문자 n-gram(1초 미만)보다 훨씬 느리지만, 이 프로토타입
규모에서는 감내할 만한 수준.

**설치 관련 주의(Windows)**: `sentence-transformers`가 끌고오는 torch
패키지의 라이선스 폴더가 경로가 매우 깊어서, Windows의 기본 경로 길이
제한(260자)에 걸려 설치가 실패할 수 있음. 이 경우 `pip install --target`
으로 훨씬 짧은 경로(예: 프로젝트 폴더 바로 아래 `pylibs/`)에 설치하고
그 경로를 `sys.path`에 추가하는 식으로 우회함 — 이 프로젝트에서도
`backend/pylibs`에 그렇게 설치돼 있음.
"""

from __future__ import annotations

import sys
from pathlib import Path

import numpy as np

# Windows 경로 길이 제한 우회로 backend/pylibs에 별도 설치된 경우를 위한
# 폴백. 정식 site-packages에 sentence-transformers가 있으면 이 경로는
# 그냥 무시됨(뒤에서부터 찾으므로 site-packages가 우선).
_PYLIBS = Path(__file__).parent / "pylibs"
if _PYLIBS.is_dir() and str(_PYLIBS) not in sys.path:
    sys.path.append(str(_PYLIBS))

_MODEL_NAME = "jhgan/ko-sroberta-multitask"
_model = None


def _get_model():
    global _model
    if _model is None:
        from sentence_transformers import SentenceTransformer

        _model = SentenceTransformer(_MODEL_NAME)
    return _model


def embed(texts: list[str]) -> np.ndarray:
    """텍스트 리스트를 정규화된(코사인 유사도용) 임베딩 행렬로 변환."""
    if not texts:
        return np.zeros((0, _get_model().get_sentence_embedding_dimension()))
    return _get_model().encode(texts, show_progress_bar=False, normalize_embeddings=True)
