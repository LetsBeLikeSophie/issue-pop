"""이슈팝 SNS 카드 렌더러.

/trending 응답(list[dict])을 받아 인스타그램 세로 카드(1080x1350, 4:5) PNG를 만든다.
스토어 피처 그래픽과 같은 톤: 네이비 배경 + 흰 종이 목록 + 노란 하이라이트.
"""
from __future__ import annotations

import io
import os
from datetime import datetime
from zoneinfo import ZoneInfo

from PIL import Image, ImageDraw, ImageFont

W, H = 1080, 1350
NAVY = (23, 53, 107)
NAVY_SOFT = (52, 84, 140)
YELLOW = (255, 210, 63)
WHITE = (255, 255, 255)
PAPER = (250, 250, 247)
INK = (20, 22, 28)
INK_SOFT = (92, 96, 106)
INK_FAINT = (150, 154, 162)
LINE = (226, 226, 222)

# 서버: apt 패키지 fonts-noto-cjk + fonts-noto-cjk-extra(Black/Medium 굵기는 extra에 있음)가 여기에 깔림.
# 로컬(Windows)에서 미리 볼 땐 SOCIAL_FONT_DIR=C:/Windows/Fonts 처럼 NotoSansKR-VF.ttf가 있는 폴더를 주면
# 가변 폰트에서 같은 굵기를 골라 씀.
FONT_DIR = os.environ.get("SOCIAL_FONT_DIR") or "/usr/share/fonts/opentype/noto"
KR = 1  # .ttc 안에서 Noto Sans CJK KR 인덱스
WEEKDAYS = "월화수목금토일"


def _font(weight: str, size: int) -> ImageFont.FreeTypeFont:
    ttc = f"{FONT_DIR}/NotoSansCJK-{weight}.ttc"
    if os.path.exists(ttc):
        return ImageFont.truetype(ttc, size, index=KR)
    f = ImageFont.truetype(f"{FONT_DIR}/NotoSansKR-VF.ttf", size)
    f.set_variation_by_name(weight)
    return f


def _fit(draw: ImageDraw.ImageDraw, text: str, font, max_w: int) -> str:
    if draw.textlength(text, font=font) <= max_w:
        return text
    while text and draw.textlength(text + "…", font=font) > max_w:
        text = text[:-1]
    return text.rstrip() + "…"


def _keyword(issue: dict) -> str:
    kw = issue.get("keyword") or ""
    if not kw and issue.get("keywords"):
        kw = issue["keywords"][0]
    return kw.replace(",", " ").strip()


def render_card(issues: list[dict], now: datetime | None = None, top_n: int = 5) -> bytes:
    now = now or datetime.now(ZoneInfo("Asia/Seoul"))
    issues = issues[:top_n]

    img = Image.new("RGB", (W, H), NAVY)
    d = ImageDraw.Draw(img)

    # 배경 장식: 기울어진 종이 두 장
    deco = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    dd = ImageDraw.Draw(deco)
    dd.polygon([(760, 120), (1120, 60), (1180, 700), (820, 760)], fill=NAVY_SOFT + (120,))
    dd.polygon([(-80, 980), (300, 930), (340, 1420), (-40, 1460)], fill=NAVY_SOFT + (90,))
    img.paste(deco, (0, 0), deco)

    # 로고
    f_logo = _font("Black", 46)
    d.text((80, 78), "Issue", font=f_logo, fill=WHITE)
    x_pop = 80 + d.textlength("Issue ", font=f_logo)
    d.text((x_pop, 78), "Pop", font=f_logo, fill=WHITE)
    pop_w = d.textlength("Pop", font=f_logo)
    d.rounded_rectangle([x_pop, 138, x_pop + pop_w, 146], radius=4, fill=YELLOW)

    # 헤드라인
    f_h1 = _font("Black", 76)
    d.text((80, 190), "오늘 가장 많이", font=f_h1, fill=WHITE)
    hl = "보도된 이슈"
    hl_w = d.textlength(hl, font=f_h1)
    d.rounded_rectangle([72, 292, 72 + hl_w + 24, 392], radius=14, fill=YELLOW)
    d.text((84, 290), hl, font=f_h1, fill=INK)
    d.text((84 + hl_w + 30, 290), "TOP 5", font=f_h1, fill=WHITE)

    date_txt = f"{now.month}월 {now.day}일 ({WEEKDAYS[now.weekday()]}) {now.hour:02d}:{now.minute:02d} 기준"
    d.text((82, 420), date_txt, font=_font("Medium", 32), fill=(205, 214, 232))

    # 흰 종이 목록
    px0, py0, px1, py1 = 60, 500, W - 60, 1200
    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle([px0 + 10, py0 + 14, px1 + 10, py1 + 14], radius=28, fill=(0, 0, 0, 60))
    img.paste(shadow, (0, 0), shadow)
    d.rounded_rectangle([px0, py0, px1, py1], radius=28, fill=PAPER)

    row_h = (py1 - py0 - 40) // max(len(issues), 1)
    f_rank = _font("Bold", 30)
    f_kw = _font("Black", 58)
    f_title = _font("Regular", 27)
    f_meta = _font("Medium", 25)
    f_count = _font("Black", 40)
    f_unit = _font("Bold", 26)

    for i, it in enumerate(issues):
        top = py0 + 20 + i * row_h
        cy = top + 18
        d.text((px0 + 44, cy + 16), f"{i + 1:02d}", font=f_rank, fill=INK_FAINT)

        # 오른쪽: 기사 수
        count = str(it.get("article_count", 0))
        unit_w = d.textlength("건", font=f_unit)
        cnt_w = d.textlength(count, font=f_count)
        cx = px1 - 44 - unit_w
        d.text((cx, cy + 14), "건", font=f_unit, fill=NAVY)
        d.text((cx - cnt_w - 4, cy), count, font=f_count, fill=NAVY)

        kx = px0 + 112
        kw_max = int(cx - cnt_w - 40 - kx)
        kw = _fit(d, _keyword(it), f_kw, kw_max)
        kw_w = d.textlength(kw, font=f_kw)
        if i == 0:
            d.rounded_rectangle([kx - 8, cy + 44, kx + kw_w + 8, cy + 76], radius=6, fill=YELLOW)
        d.text((kx, cy - 6), kw, font=f_kw, fill=INK)

        outlets = f"{it.get('outlet_count', 0)}개 매체"
        d.text((px1 - 44 - d.textlength(outlets, font=f_meta), cy + 78), outlets, font=f_meta, fill=INK_FAINT)

        cat = it.get("category", "")
        cat_w = d.textlength(cat, font=f_meta)
        d.rounded_rectangle([kx, cy + 78, kx + cat_w + 20, cy + 112], radius=8, fill=(232, 236, 244))
        d.text((kx + 10, cy + 77), cat, font=f_meta, fill=NAVY)
        tx = kx + cat_w + 34
        out_w = d.textlength(outlets, font=f_meta)
        title = _fit(d, it.get("representative_title", ""), f_title, int(px1 - 44 - out_w - 24 - tx))
        d.text((tx, cy + 76), title, font=f_title, fill=INK_SOFT)

        if i < len(issues) - 1:
            d.line([px0 + 40, top + row_h - 2, px1 - 40, top + row_h - 2], fill=LINE, width=2)

    # 푸터
    f_foot = _font("Medium", 28)
    d.text((80, 1240), "여러 언론사 보도량 기준으로 묶은 오늘의 이슈", font=f_foot, fill=(205, 214, 232))
    d.text((80, 1282), "Google Play에서 ‘이슈팝’ 검색", font=_font("Bold", 28), fill=YELLOW)

    buf = io.BytesIO()
    img.save(buf, "PNG", optimize=True)
    return buf.getvalue()


def caption(issues: list[dict], now: datetime | None = None, top_n: int = 5) -> str:
    now = now or datetime.now(ZoneInfo("Asia/Seoul"))
    lines = [f"📰 {now.month}월 {now.day}일 오늘 가장 많이 보도된 이슈 TOP {min(top_n, len(issues))}", ""]
    for i, it in enumerate(issues[:top_n], 1):
        lines.append(f"{i}. {_keyword(it)} — {it.get('outlet_count', 0)}개 매체 · {it.get('article_count', 0)}건")
    lines += ["", "여러 언론사 기사를 이슈별로 묶어 보도량 순으로 보여 드려요.",
              "앱 ‘이슈팝’ (Google Play)", "", "#오늘의뉴스 #뉴스요약 #이슈 #시사 #이슈팝"]
    return "\n".join(lines)
