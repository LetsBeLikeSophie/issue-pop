"""Ripe Weekly 홍보(매주, 한국어 한 장 + 영어 한 장) — 인스타 피드 + Threads.

Ripe Weekly: 궁금한 분야를 한 줄로 적으면 AI가 매주 많은 글을 읽고 지금 뜨는 것만 3분짜리 리포트로 보내 주는 앱
(저장소 ripe-weekly, 한국어·영어·일본어 지원). **링크는 넣지 않음**(2026-11-27 사용자 결정): 웹 버전은 아직 무료·유료
확인 없이 AI 토큰을 써서, 공개 링크로 사람이 몰리면 비용이 나감. 출시 전까지는 "팔로우해 두면 소식 알려 드림"으로만.
그림은 ripe-weekly/marketing/threads-2026-11-20.png 톤 그대로: 크림 바탕 + 파란 큰 제목(Black Han Sans), 아래
갈색 띠 + 손글씨 로고(Gochi Hand) + 리포트 카드(막 뜨는 중 → 오르는 중 → 식는 중 곡선). 글꼴은 assets/fonts(OFL).
카드 속 주제·항목은 "이런 식으로 보여 준다"는 **예시 그림**이고 실제 트렌드 데이터가 아님 — 글에서도 예시라고 씀.
주마다 SETS를 돌려 씀(ISO 주 번호). 문구는 Claude 없이 미리 써 둔 것(짧고, 매주 같은 품질).
"""
from __future__ import annotations

import io
import math
from datetime import datetime
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

from social_card import _font

FONTS = Path(__file__).resolve().parent / "assets" / "fonts"
W, H = 1080, 1350
BG = (247, 247, 244)
BLUE = (47, 95, 179)
TAN = (200, 147, 94)
INK = (27, 27, 27)
TEXT3 = (85, 85, 85)
WHITE = (255, 255, 255)
STAGE = {"new": ((232, 238, 249), (47, 95, 179), (47, 95, 179)),
         "rising": ((255, 227, 194), (122, 59, 0), (226, 98, 27)),
         "cooling": ((220, 230, 242), (31, 58, 92), (90, 123, 168))}

LANG = {
    "ko": {"corner": "매주 3분 트렌드 리포트", "week": "이번 주 · 3분",
           "labels": {"new": "막 뜨는 중", "rising": "오르는 중", "cooling": "식는 중"},
           "axis": ["막 뜨기 시작", "정점", "식는 중"],
           "sub": [[("궁금한 분야를 ", False), ("한 줄", True), ("만 적으면", False)],
                   [("지금 뜨는 것만 골라 ", False), ("매주 보내 드려요", True)]]},
    "en": {"corner": "A 3-minute weekly trend report", "week": "This week · 3 min",
           "labels": {"new": "New", "rising": "Rising", "cooling": "Cooling"},
           "axis": ["Just started", "Peak", "Cooling"],
           "sub": [[("Write ", False), ("one line", True), (" about what you're into.", False)],
                   [("Get only what's rising, ", False), ("every week.", True)]]},
}

# 주마다 돌아가며: 큰 제목 + 예시 주제와 항목(막 뜨는 중·오르는 중·식는 중)
SETS = {
    "ko": [
        {"head": ["검색은 그만,", "한 줄만", "적으세요."], "topic": "러닝",
         "items": ["러닝 크루", "카본 러닝화", "맨발 걷기"]},
        {"head": ["트렌드,", "이제 훑기만", "하세요."], "topic": "홈카페",
         "items": ["콜드브루 원액", "핸드드립 키트", "달고나"]},
        {"head": ["매주 3분이면", "충분해요."], "topic": "AI 도구",
         "items": ["AI 에이전트", "바이브 코딩", "프롬프트 모음집"]},
        {"head": ["알아서 읽고,", "골라서", "보내 드려요."], "topic": "캠핑",
         "items": ["백패킹", "차박", "글램핑"]},
    ],
    "en": [
        {"head": ["Stop chasing", "trends.", "Skim them."], "topic": "Home coffee",
         "items": ["Cold brew", "Pour-over kits", "Dalgona"]},
        {"head": ["One line in.", "What's rising,", "out."], "topic": "Running",
         "items": ["Run clubs", "Carbon shoes", "Barefoot running"]},
        {"head": ["3 minutes", "a week.", "That's it."], "topic": "AI tools",
         "items": ["AI agents", "Vibe coding", "Prompt packs"]},
        {"head": ["We read it all.", "You get what", "matters."], "topic": "Camping",
         "items": ["Backpacking", "Car camping", "Glamping"]},
    ],
}


def pick(lang: str, now: datetime) -> dict:
    sets = SETS[lang]
    return sets[now.isocalendar()[1] % len(sets)]


def caption(lang: str, s: dict) -> str:
    if lang == "ko":
        return (f"궁금한 분야를 한 줄만 적으면, AI가 매주 많은 글을 읽고 지금 뜨는 것만 3분짜리 리포트로 보내 드려요.\n\n"
                f"그림은 '{s['topic']}' 예시 — 막 뜨는 것, 오르는 것, 식는 것을 한눈에.\n\n"
                f"곧 만나요 — 출시 소식은 팔로우해 두시면 알려 드릴게요.\n\n"
                f"#RipeWeekly #트렌드 #트렌드리포트 #뉴스레터 #생산성")
    return (f"Write one line about what you're into. Every week, AI reads a ton so you don't have to — "
            f"and sends you a 3-minute report on what's rising.\n\n"
            f"Pictured: an example for \"{s['topic']}\" — what's new, what's rising, what's cooling.\n\n"
            f"Coming soon — follow for launch updates.\n\n"
            f"#RipeWeekly #trends #trendreport #newsletter #productivity")


def threads_text(lang: str, s: dict) -> str:
    """Threads는 소피 말투(반말, 짧은 줄, 👾💜) — devlog.THREADS_TONE 참고. 인스타 캡션은 존댓말 그대로."""
    if lang == "ko":
        from devlog import mix_jamo  # 쪼개 쓰기는 주마다 섞어서(예시 주제로 정해짐)

        return mix_jamo(f"트렌드 따라가기 너무 빠르자너💦\n그래서 ㄴ ㅏ를 위해 만들구 이쏘👾\n\n"
                f"궁금한 거 한 줄만 적으면\n매주 지금 뜨는 것만 3분 리포트로 보내줌\n"
                f"예: {s['topic']} → 막 뜨는 중 · 오르는 중 · 식는 중\n\n"
                f"곧 나와! 팔로우해 두면 알려줄게💜", s["topic"])
    return (f"trends move way too fast 💦\nso I built this 👾\n\n"
            f"write one line about what you're into\n→ every week, a 3-min report on what's rising (and cooling)\n"
            f"e.g. {s['topic']}\n\n"
            f"coming soon! follow and I'll let you know 💜")


def _f(name: str, size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(FONTS / name), size)


def render(lang: str, s: dict) -> bytes:
    L = LANG[lang]
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)
    d.text((66, 60), "RIPE WEEKLY", font=_font("Bold", 30), fill=BLUE)
    fc = _font("Bold", 30)
    d.text((W - 66 - d.textlength(L["corner"], font=fc), 60), L["corner"], font=fc, fill=BLUE)

    size = 150
    while size > 80 and max(d.textlength(ln, font=_f("BlackHanSans_400Regular.ttf", size)) for ln in s["head"]) > W - 62 - 230:
        size -= 4  # 오른쪽 열매 아이콘과 안 겹치게 줄임
    hf = _f("BlackHanSans_400Regular.ttf", size)
    y = 120
    for ln in s["head"]:
        d.text((62, y), ln, font=hf, fill=BLUE)
        y += int(size * 1.05)

    cx, cy, r = 925, 250, 63  # 동그란 열매(기존 홍보 이미지의 아이콘 모양)
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=BLUE)
    d.chord([cx - r + 14, cy - r + 14, cx + r - 14, cy + r - 14], 180, 360, fill=BG)
    d.line([cx, cy - r, cx + 6, cy - r - 22], fill=BLUE, width=8)
    d.ellipse([cx + 10, cy - r - 40, cx + 58, cy - r - 14], fill=BLUE)

    sf, sb = _font("Regular", 38), _font("Bold", 38)
    yy = 630
    for parts in L["sub"]:
        x = 66
        for txt, bold in parts:
            d.text((x, yy), txt, font=sb if bold else sf, fill=INK)
            x += d.textlength(txt, font=sb if bold else sf)
        yy += 54

    d.rectangle([0, 830, W, H], fill=TAN)
    logo = Image.new("RGBA", (520, 330), (0, 0, 0, 0))
    ld = ImageDraw.Draw(logo)
    ld.text((10, 20), "Ripe", font=_f("GochiHand_400Regular.ttf", 108), fill=WHITE)
    ld.text((36, 130), "Weekly", font=_f("GochiHand_400Regular.ttf", 108), fill=WHITE)
    logo = logo.rotate(8, resample=Image.BICUBIC, expand=True)
    img.paste(logo, (24, 950), logo)

    box = (484, 855, 1024, 1280)
    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle([box[0] + 6, box[1] + 10, box[2] + 6, box[3] + 10], radius=34,
                                             fill=(0, 0, 0, 40))
    img.paste(shadow, (0, 0), shadow)
    d.rounded_rectangle(box, radius=34, fill=WHITE)
    d.text((box[0] + 38, box[1] + 40), s["topic"], font=_f("BlackHanSans_400Regular.ttf", 46), fill=INK)
    fw = _font("Regular", 24)
    d.text((box[2] - 36 - d.textlength(L["week"], font=fw), box[1] + 14), L["week"], font=fw, fill=TEXT3)
    x = box[0] + 36
    ft = _font("Bold", 26)
    for st in ("new", "rising", "cooling"):
        t = f"{L['labels'][st]} 1"
        tw = d.textlength(t, font=ft)
        d.rounded_rectangle([x, box[1] + 112, x + tw + 32, box[1] + 162], radius=25, fill=STAGE[st][0])
        d.text((x + 16, box[1] + 118), t, font=ft, fill=STAGE[st][1])
        x += tw + 44

    gx0, gx1, gy0, gy1 = box[0] + 60, box[2] - 60, box[1] + 200, box[1] + 370
    pts = [(gx0 + (gx1 - gx0) * t, gy1 - (gy1 - gy0) * math.exp(-((t - 0.5) ** 2) / 0.045))
           for t in (i / 100 for i in range(101))]
    d.line(pts, fill=(213, 220, 236), width=14, joint="curve")
    d.line(pts, fill=BLUE, width=5, joint="curve")
    fl = _font("Medium", 22)
    for i, lab in enumerate(L["axis"]):
        tx = [gx0 - 10, (gx0 + gx1) / 2 - 20, gx1 - 70][i]
        d.text((tx, gy1 + 16), lab, font=fl, fill=TEXT3)
    fi = _font("Bold", 24)
    for txt, st, t in zip(s["items"], ("new", "rising", "cooling"), (0.24, 0.42, 0.8)):
        px, py = pts[int(t * 100)]
        d.ellipse([px - 11, py - 11, px + 11, py + 11], fill=STAGE[st][2], outline=WHITE, width=3)
        tw = d.textlength(txt, font=fi)
        if t < 0.35:
            tx, ty = px - tw - 8, py - 50
        elif t > 0.65:
            tx, ty = px + 6, py - 50
        else:
            tx, ty = px - tw - 22, py - 16
        tx = min(max(tx, box[0] + 16), box[2] - 16 - tw)
        d.rounded_rectangle([tx - 8, ty - 2, tx + tw + 8, ty + 34], radius=10, fill=WHITE)
        d.text((tx, ty), txt, font=fi, fill=STAGE[st][1] if st != "new" else BLUE)

    buf = io.BytesIO()
    img.save(buf, "PNG", optimize=True)
    return buf.getvalue()
