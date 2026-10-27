# -*- coding: utf-8 -*-
"""이미 쓴 오늘의 단어는 다시 안 뽑힘 — `python3 test_word_exclude.py` (kiwipiepy 필요: test_pipeline.py와 같은 환경)."""
import datetime as dt
import os
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from sqlmodel import SQLModel, create_engine

import api
import db
import word_of_day

# --- 1) pick_word: exclude에 든 단어는 후보에서 빠짐(사전 조회도 안 함) ---
looked_up = []
word_of_day.dictionary.lookup = lambda w: looked_up.append(w) or f"{w}의 뜻"
word_of_day.llm.pick_best_word = lambda cands: cands[0]["word"]  # 후보 중 첫 번째(반복 최다)

cache = {
    "i1": {"articles": [{"title": "정부 승부수 던졌다"}, {"title": "여당 승부수 논란"}, {"title": "속도전 돌입한 국회"}]},
    "i2": {"articles": [{"title": "야당 승부수 비판"}, {"title": "속도전 예고한 정부"}]},
}
picked = word_of_day.pick_word(cache)
assert picked is not None and picked[0] == "승부수", picked  # 제일 많이 반복된 단어

looked_up.clear()
picked = word_of_day.pick_word(cache, exclude={"승부수"})
assert picked is not None and picked[0] == "속도전", picked
assert "승부수" not in looked_up, "이미 쓴 단어는 사전 조회도 안 해야 함"

assert word_of_day.pick_word(cache, exclude={"승부수", "속도전"}) is None  # 후보가 전부 쓴 단어면 None

# --- 2) api._pick_unused_word: 평소엔 쓴 단어 전체 제외, 새 후보가 없으면 최근 30일 것만 제외하고 재시도 ---
tmp = tempfile.NamedTemporaryFile(suffix=".db", delete=False)
tmp.close()
db.engine = create_engine(f"sqlite:///{tmp.name}")
SQLModel.metadata.create_all(db.engine)
api._cache.clear()
api._cache.update(cache)

today = dt.datetime.now(api.KST)
old_day = (today - dt.timedelta(days=60)).strftime("%Y-%m-%d")   # 오래전에 쓴 단어
recent_day = (today - dt.timedelta(days=5)).strftime("%Y-%m-%d")  # 최근에 쓴 단어
with db.get_session() as s:
    s.add(db.WordOfDay(date=old_day, word="승부수", example="", definition="x"))
    s.add(db.WordOfDay(date=recent_day, word="속도전", example="", definition="x"))
    s.commit()

with db.get_session() as s:
    # 둘 다 이미 쓴 단어 → 1차(전체 제외)는 후보가 없고, 2차(최근 30일만 제외)에서 오래전에 쓴 "승부수"가 다시 나옴
    picked = api._pick_unused_word(s)
    assert picked is not None and picked[0] == "승부수", picked

with db.get_session() as s:
    # 최근에 쓴 단어가 전부면 2차에서도 후보가 없어 None(그날은 쉬었다가 30분 뒤 다시 시도)
    s.add(db.WordOfDay(date=today.strftime("%Y-%m-%d"), word="승부수", example="", definition="x"))
    s.commit()
    assert api._pick_unused_word(s) is None

print("test_word_exclude: ALL OK")
