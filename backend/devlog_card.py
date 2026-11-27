"""주간 개발 에피소드 캐러셀(1080x1350, 4:5) — 소피앱스 브랜드 톤.

크림 종이 배경 + 굵은 잉크 외곽선 + 스티커 그림자(오프셋 그림자, 그라데이션 없음) + 라벤더/볼터치 포인트.
로고는 assets/brand의 원본 PNG를 그대로 씀(다시 그리지 않음).
한글 제목은 브랜드 글꼴 Jua(SOCIAL_FONT_DIR에 Jua-Regular.ttf가 있으면), 없으면 Noto Sans CJK Black.
"""
from __future__ import annotations

import io
import os
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

from social_card import FONT_DIR, _font

W, H = 1080, 1350
INK = (59, 54, 64)
LAVENDER = (195, 174, 240)
LAVENDER_INK = (138, 107, 216)
CHEEK = (247, 169, 160)
PAPER = (246, 242, 231)
WHITE = (255, 255, 255)
SOFT = (120, 114, 128)
OUTLINE = 5
SHADOW = 10

ASSETS = Path(__file__).resolve().parent / "assets" / "brand"


def _title_font(size: int) -> ImageFont.FreeTypeFont:
    jua = Path(FONT_DIR) / "Jua-Regular.ttf"
    if jua.exists():
        return ImageFont.truetype(str(jua), size)
    return _font("Black", size)


def _logo(height: int, symbol: bool = False) -> Image.Image:
    im = Image.open(ASSETS / ("sophie-apps-symbol-512.png" if symbol else "sophie-apps-logo.png")).convert("RGBA")
    return im.resize((round(im.width * height / im.height), height), Image.LANCZOS)


def _plain(text: str) -> str:
    """이모지·특수 기호는 글꼴에 없어 네모(□)로 나와서 뺌."""
    out = "".join(ch for ch in text if ord(ch) < 0x2190 or 0x3000 <= ord(ch) <= 0xD7FF or 0xFF00 <= ord(ch) <= 0xFFEF)
    return " ".join(out.split())


def _wrap(d: ImageDraw.ImageDraw, text: str, font, max_w: int, max_lines: int) -> list[str]:
    """한 글자씩 넣어 보며 줄바꿈(한국어는 띄어쓰기가 적어서). 넘치면 마지막 줄 말줄임."""
    text = _plain(text)
    lines, cur = [], ""
    for ch in text:
        if ch == "\n" or d.textlength(cur + ch, font=font) > max_w:
            lines.append(cur.rstrip())
            cur = "" if ch in "\n " else ch
        else:
            cur += ch
    if cur.strip():
        lines.append(cur.rstrip())
    if len(lines) > max_lines:
        last = lines[max_lines - 1]
        while last and d.textlength(last + "…", font=font) > max_w:
            last = last[:-1]
        lines = lines[: max_lines - 1] + [last.rstrip() + "…"]
    return lines


def _sticker(d: ImageDraw.ImageDraw, box, fill, radius=28):
    x0, y0, x1, y1 = box
    d.rounded_rectangle([x0 + SHADOW, y0 + SHADOW, x1 + SHADOW, y1 + SHADOW], radius=radius, fill=INK)
    d.rounded_rectangle(box, radius=radius, fill=fill, outline=INK, width=OUTLINE)


def _pill(d: ImageDraw.ImageDraw, x, y, text, font, fill, pad=(22, 10)) -> int:
    w = d.textlength(text, font=font)
    h = font.size + pad[1] * 2 + 4
    d.rounded_rectangle([x + 4, y + 5, x + w + pad[0] * 2 + 4, y + h + 5], radius=h // 2, fill=INK)
    d.rounded_rectangle([x, y, x + w + pad[0] * 2, y + h], radius=h // 2, fill=fill, outline=INK, width=4)
    d.text((x + pad[0], y + pad[1] - 2), text, font=font, fill=INK)
    return int(x + w + pad[0] * 2)


def _sparkle(d: ImageDraw.ImageDraw, cx, cy, r, fill):
    """손그림 반짝이(네 꼭지 별)."""
    k = r * 0.28
    d.polygon([(cx, cy - r), (cx + k, cy - k), (cx + r, cy), (cx + k, cy + k),
               (cx, cy + r), (cx - k, cy + k), (cx - r, cy), (cx - k, cy - k)], fill=fill, outline=INK, width=3)


def _base(page: str) -> tuple[Image.Image, ImageDraw.ImageDraw]:
    img = Image.new("RGB", (W, H), PAPER)
    d = ImageDraw.Draw(img)
    logo = _logo(54)
    img.paste(logo, (72, 64), logo)
    f = _font("Bold", 30)
    d.text((W - 72 - d.textlength(page, font=f), 74), page, font=f, fill=SOFT)
    d.text((72, H - 92), "@itssophie.dev · 만드는 과정 공개", font=_font("Medium", 30), fill=SOFT)
    return img, d


def _png(img: Image.Image) -> bytes:
    buf = io.BytesIO()
    img.save(buf, "PNG", optimize=True)
    return buf.getvalue()


def render_cover(ep: dict, pages: int) -> bytes:
    img, d = _base(f"1/{pages}")
    _pill(d, 72, 190, "BUILD LOG · 이번 주 만든 것", _font("Bold", 34), LAVENDER)
    d.text((76, 280), ep["span"], font=_font("Medium", 38), fill=SOFT)

    ft = _title_font(104)
    y = 350
    for ln in _wrap(d, ep["title"], ft, W - 160, 3):
        d.text((72, y), ln, font=ft, fill=INK)
        y += 128
    fi = _font("Regular", 40)
    for ln in _wrap(d, ep["intro"], fi, W - 160, 2):
        d.text((76, y + 16), ln, font=fi, fill=INK)
        y += 56

    # 이번 주 숫자 + 프로젝트 칩
    box = (72, max(y + 70, 760), W - 72 - SHADOW, max(y + 70, 760) + 300)
    _sticker(d, box, WHITE)
    fn = _title_font(84)
    num = str(ep["total"])
    d.text((120, box[1] + 30), num, font=fn, fill=LAVENDER_INK)
    d.text((120 + d.textlength(num, font=fn), box[1] + 70), f"개 커밋 · 프로젝트 {len(ep['projects'])}개",
           font=_font("Bold", 40), fill=INK)
    x, yy = 120, box[1] + 160
    fc = _font("Bold", 30)
    for p in ep["projects"]:
        w = d.textlength(p["name"], font=fc) + 44 + 14
        if x + w > box[2] - 40:
            x, yy = 120, yy + 70
            if yy > box[3] - 80:
                break
        x = _pill(d, x, yy, _plain(p["name"]), fc, PAPER, pad=(18, 8)) + 14

    sym = _logo(150, symbol=True)  # 제목(y 350~)과 안 겹치게 위쪽에
    img.paste(sym, (W - 72 - 150, 150), sym)
    _sparkle(d, W - 260, 175, 22, CHEEK)
    _sparkle(d, W - 60, 300, 16, LAVENDER)
    return _png(img)


def render_project(p: dict, page: int, pages: int) -> bytes:
    img, d = _base(f"{page}/{pages}")
    fc = _font("Bold", 36)
    x = _pill(d, 72, 190, _plain(p["name"]), fc, LAVENDER)
    _pill(d, x + 18, 190, f"커밋 {p['count']}개", fc, CHEEK)

    ft = _title_font(92)
    y = 310
    for ln in _wrap(d, p["headline"], ft, W - 160, 2):
        d.text((72, y), ln, font=ft, fill=INK)
        y += 116

    fs = _font("Regular", 40)
    story = _wrap(d, p["story"], fs, W - 72 * 2 - 100 - SHADOW, 4)
    top = max(y + 30, 560)
    box = (72, top, W - 72 - SHADOW, top + 70 + len(story) * 60)
    _sticker(d, box, WHITE)
    for i, ln in enumerate(story):
        d.text((120, top + 34 + i * 60), ln, font=fs, fill=INK)

    fp = _font("Bold", 40)
    yy = box[3] + 70
    for pt in p["points"][:3]:
        d.ellipse([80, yy + 12, 108, yy + 40], fill=LAVENDER, outline=INK, width=4)
        lines = _wrap(d, pt, fp, W - 220, 2)
        for ln in lines:
            d.text((134, yy), ln, font=fp, fill=INK)
            yy += 56
        yy += 26
        if yy > H - 200:
            break
    _sparkle(d, W - 110, 222, 22, CHEEK)
    return _png(img)


def render_episode(ep: dict) -> list[bytes]:
    """[표지, 프로젝트1, ...] PNG 바이트 목록(인스타 캐러셀은 2~10장)."""
    pages = 1 + len(ep["projects"])
    return [render_cover(ep, pages)] + [render_project(p, i + 2, pages) for i, p in enumerate(ep["projects"])]
