# -*- coding: utf-8 -*-
"""카테고리 이어받기(기사 링크 겹침) / 작은 이슈 LLM 생략 테스트 — `python3 test_category_inherit.py`.

실제 DB와 Anthropic 호출을 안 건드림: 임시 SQLite로 엔진을 갈아끼우고 LLM 분류 함수는 호출 횟수를 세는 가짜로 바꿈."""
import os
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from sqlmodel import SQLModel, create_engine

import api
import category
import db

tmp = tempfile.NamedTemporaryFile(suffix=".db", delete=False)
tmp.close()
db.engine = create_engine(f"sqlite:///{tmp.name}")
SQLModel.metadata.create_all(db.engine)
db.init_db()  # 인덱스 생성 구문이 오류 없이 도는지(여러 번 불려도 안전한지)까지 확인
db.init_db()

calls: list[list[str]] = []


def fake_llm(keywords, title):
    calls.append(list(keywords))
    return "경제"


category.classify_category_llm = fake_llm


def links(prefix, n):
    return [f"https://x/{prefix}/{i}" for i in range(n)]


def cluster(cid, keywords, link_list, cat="사회"):
    return {
        "id": cid,
        "keywords": keywords,
        "keyword": keywords[0],
        "representative_title": "제목",
        "category": cat,
        "article_count": len(link_list),
        "outlet_count": 2,
        "articles": [{"outlet": "A", "title": "t", "link": l} for l in link_list],
    }


def store(cid, kw, link_list, cat):
    with db.get_session() as s:
        s.add(db.Issue(id=cid, keyword=kw, keywords_json=f'["{kw}"]', category=cat, representative_title="t",
                       article_count=len(link_list), outlet_count=2))
        for l in link_list:
            s.add(db.Article(issue_id=cid, outlet="A", title="t", link=l))
        s.commit()


# 이전 갱신에서 저장된 이슈: 큰 이슈(5건, 정치), 작은 이슈(2건, 연예)
store("old_big", "대통령", links("big", 5), "정치")
store("old_small", "배우", links("small", 2), "연예")

# 1) 기사 80% 겹침 → 이어받음(LLM 호출 없음), 키워드가 바뀌었어도
c1 = cluster("n1", ["대통령", "회담"], links("big", 4) + links("new1", 1))
# 2) 겹침 절반 미만 → 이어받기 안 됨, 기사 3건 이상이라 LLM 호출
c2 = cluster("n2", ["환율", "상승"], links("big", 1) + links("new2", 4))
# 3) 작은 이슈에만 겹침 → 원본이 작아서 인정 안 됨, 새 이슈도 2건이라 LLM 안 부르고 규칙 기반 유지
c3 = cluster("n3", ["배우", "열애"], links("small", 2), cat="사회")
# 4) 아무것도 안 겹치는 2건짜리 → LLM 안 부름, 규칙 기반 유지
c4 = cluster("n4", ["날씨"], links("new4", 2), cat="사회")
# 5) 아무것도 안 겹치는 3건짜리 → LLM 호출
c5 = cluster("n5", ["지진", "발생"], links("new5", 3), cat="사회")

clusters = {c["id"]: c for c in (c1, c2, c3, c4, c5)}
api._classify_categories(clusters)

assert c1["category"] == "정치", c1["category"]
assert c2["category"] == "경제"
assert c3["category"] == "사회"
assert c4["category"] == "사회"
assert c5["category"] == "경제"
assert sorted(calls) == [["지진", "발생"], ["환율", "상승"]], calls

# 이어받은 값은 키워드 캐시에 안 남음(LLM이 직접 답한 값만 남음)
with db.get_session() as s:
    assert s.get(db.CategoryCache, "대통령|회담") is None
    assert s.get(db.CategoryCache, "환율|상승") is not None

# 다시 돌려도 캐시된 건 안 부름
calls.clear()
api._classify_categories({c["id"]: c for c in (c2, c5)})
assert calls == []

# 겹침이 같은 원본에 여러 개일 땐 겹침이 가장 많은 쪽을 고름
store("old_other", "주가", links("mix", 3), "경제")
store("old_mix", "금리", links("big", 3) + links("mix", 1), "사회")
with db.get_session() as s:
    got = db.find_inherited_categories(s, {"k": links("mix", 3)})
    assert got == {"k": "경제"}, got
    assert db.find_inherited_categories(s, {"k": []}) == {}

# 클러스터 감사는 큰 이슈만 봄
api._cache.clear()
api._cache["s"] = {"keyword": "작은", "category": "사회", "article_count": 2, "articles": []}
api._cache["b"] = {"keyword": "큰", "category": "사회", "article_count": 3, "articles": [{"title": "t"}]}
seen = []
api.cluster_audit.iter_batches = lambda cl: (seen.extend(c["issue_id"] for c in cl) or [])
api._run_cluster_audit()
assert seen == ["b"], seen

print("test_category_inherit: ALL OK")
