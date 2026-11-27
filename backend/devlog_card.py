"""개발 일지 이미지(1080x1350, 4:5, 한 장) — 짧고 임팩트 있게(2026-11-27 사용자 피드백: 장수·글이 많으면 3초 안에 넘김).

앱 에피소드는 소재마다 한 장:
  A 한 줄 임팩트(story) — 앱 색 배경 + 큰 글씨 두 마디
  C 개발 일지 메모(new) — 메모지에 3~4줄, 머리띠는 앱 색
  D 숫자 한 방(vibe)   — 소피앱스 라벤더 + 큰 숫자
게임 개발 일지는 화면 위주: 전 → 후 캡처를 위아래로(전 캡처가 없으면 오늘 화면 한 장).
배경색은 앱마다 다르게(devlog.APPS의 color, 없으면 앱 아이콘에서 뽑은 색, 그것도 없으면 소피앱스 라벤더 잉크).
소피앱스 로고는 구석에 작게. 로고는 assets/brand 원본 PNG를 그대로 씀.
"""
from __future__ import annotations

import io
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
SOFT = (130, 126, 136)
OUTLINE = 5
SHADOW = 10
X0 = 80

ASSETS = Path(__file__).resolve().parent / "assets" / "brand"


# ---------- 공용 ----------

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
    out = "".join(ch for ch in str(text or "")
                  if ord(ch) < 0x2190 or 0x3000 <= ord(ch) <= 0xD7FF or 0xFF00 <= ord(ch) <= 0xFFEF)
    return " ".join(out.split())


def _wrap(d: ImageDraw.ImageDraw, text: str, font, max_w: int, max_lines: int) -> list[str]:
    """띄어쓰기 단위로 줄바꿈. 한 단어가 한 줄보다 길면 그 단어만 글자 단위로. 넘치면 마지막 줄 말줄임."""
    lines, cur = [], ""
    for word in _plain(text).split(" "):
        cand = f"{cur} {word}" if cur else word
        if d.textlength(cand, font=font) <= max_w:
            cur = cand
            continue
        if cur:
            lines.append(cur)
        cur = ""
        for ch in word:
            if d.textlength(cur + ch, font=font) > max_w:
                lines.append(cur)
                cur = ch
            else:
                cur += ch
    if cur:
        lines.append(cur)
    if len(lines) > max_lines:
        last = lines[max_lines - 1]
        while last and d.textlength(last + "…", font=font) > max_w:
            last = last[:-1]
        lines = lines[: max_lines - 1] + [last.rstrip() + "…"]
    return lines


def _lines(d, x, y, text, font, max_w, max_lines, fill, gap=1.22, center=False) -> int:
    for ln in _wrap(d, text, font, max_w, max_lines):
        lx = (W - d.textlength(ln, font=font)) // 2 if center else x
        d.text((lx, y), ln, font=font, fill=fill)
        y += int(font.size * gap)
    return y


def _sticker(d: ImageDraw.ImageDraw, box, fill, radius=28):
    x0, y0, x1, y1 = box
    d.rounded_rectangle([x0 + SHADOW, y0 + SHADOW, x1 + SHADOW, y1 + SHADOW], radius=radius, fill=INK)
    d.rounded_rectangle(box, radius=radius, fill=fill, outline=INK, width=OUTLINE)


def _pill(d: ImageDraw.ImageDraw, x, y, text, font, fill, pad=(22, 10)) -> int:
    text = _plain(text)
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


def _picture(img: Image.Image, d: ImageDraw.ImageDraw, pic: Image.Image, box, radius=28) -> tuple:
    """그림을 box 안에 비율 유지로 맞추고 스티커 테두리를 둘러 붙임(가운데). 실제 그려진 영역을 돌려줌."""
    bx0, by0, bx1, by1 = box
    scale = min((bx1 - bx0) / pic.width, (by1 - by0) / pic.height)
    w, h = max(1, int(pic.width * scale)), max(1, int(pic.height * scale))
    x, y = bx0 + (bx1 - bx0 - w) // 2, by0 + (by1 - by0 - h) // 2
    _sticker(d, (x - OUTLINE, y - OUTLINE, x + w + OUTLINE, y + h + OUTLINE), WHITE, radius=radius)
    pic = pic.convert("RGBA").resize((w, h), Image.LANCZOS)
    rounded = Image.new("L", (w, h), 0)
    ImageDraw.Draw(rounded).rounded_rectangle([0, 0, w - 1, h - 1], radius=max(4, radius - OUTLINE), fill=255)
    mask = Image.composite(pic.getchannel("A"), Image.new("L", (w, h), 0), rounded)
    img.paste(pic, (x, y), mask)
    return x, y, x + w, y + h


def _corner_logo(img: Image.Image, on_color: bool) -> None:
    """오른쪽 아래 작은 소피앱스 로고. 진한 배경 위엔 흰 칩에 얹음."""
    logo = _logo(40)
    if on_color:
        ImageDraw.Draw(img).rounded_rectangle([W - X0 - logo.width - 28, H - 104, W - X0, H - 44], radius=30,
                                              fill=WHITE)
        img.paste(logo, (W - X0 - logo.width - 14, H - 94), logo)
    else:
        img.paste(logo, (W - X0 - logo.width, H - 96), logo)


def _png(img: Image.Image) -> bytes:
    buf = io.BytesIO()
    img.save(buf, "PNG", optimize=True)
    return buf.getvalue()


def _lum(c) -> float:
    return (0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]) / 255


def theme_color(color=None, icon=None) -> tuple:
    """앱 색: 지정된 색 → 아이콘에서 가장 많이 쓰인 '색다운' 색 → 소피앱스 라벤더 잉크."""
    if color:
        return tuple(color)
    if icon is not None:
        small = icon.convert("RGBA").resize((64, 64))
        counts: dict = {}
        for r, g, b, a in small.getdata():
            if a < 200:
                continue
            mx, mn = max(r, g, b), min(r, g, b)
            if mx - mn < 40 or mx < 60:  # 흰색·회색·검정 빼고
                continue
            key = (r // 24 * 24, g // 24 * 24, b // 24 * 24)
            counts[key] = counts.get(key, 0) + 1
        if counts:
            return max(counts, key=counts.get)
    return LAVENDER_INK


# ---------- A. 한 줄 임팩트(앱 이야기) ----------

def render_impact(ep: dict, color: tuple) -> bytes:
    img = Image.new("RGB", (W, H), color)
    d = ImageDraw.Draw(img)
    dark = _lum(color) < 0.62
    first = WHITE if dark else INK
    second = (INK if _lum(color) > 0.38 else LAVENDER) if dark else LAVENDER_INK
    y = _lines(d, X0, 380, ep["line1"], _title_font(116), W - 2 * X0, 2, first)
    _lines(d, X0, y + 70, ep["line2"], _title_font(100), W - 2 * X0, 2, second)
    _pill(d, X0, H - 200, ep["name"], _font("Bold", 40), WHITE)
    _corner_logo(img, on_color=True)
    return _png(img)


# ---------- C. 개발 일지 메모(새로 시작한 앱) ----------

def render_memo(ep: dict, color: tuple, date_label: str) -> bytes:
    img = Image.new("RGB", (W, H), PAPER)
    d = ImageDraw.Draw(img)
    box = (110, 220, W - 110 - SHADOW, 1120)
    _sticker(d, box, WHITE, radius=36)
    d.rounded_rectangle([box[0] + OUTLINE, box[1] + OUTLINE, box[2] - OUTLINE, box[1] + 110], radius=30, fill=color)
    d.rectangle([box[0] + OUTLINE, box[1] + 60, box[2] - OUTLINE, box[1] + 110], fill=color)
    head = WHITE if _lum(color) < 0.62 else INK
    d.text((160, box[1] + 30), _plain(f"개발 일지 · {ep['name']}"), font=_font("Bold", 44), fill=head)
    lines = ep["lines"][:4]
    accent = color if _lum(color) < 0.75 else LAVENDER_INK
    split = max(1, len(lines) - 2)  # 마지막 두 줄은 앱 색으로 강조, 그 앞에 한 칸 띄움
    y = 430
    for i, ln in enumerate(lines):
        if i == split:
            y += 50
        y = _lines(d, 170, y, ln, _title_font(76), box[2] - 170 - 60, 2, accent if i >= split else INK, gap=1.3)
    d.text((170, box[3] - 100), _plain(date_label), font=_font("Medium", 34), fill=SOFT)
    sym = _logo(190, symbol=True)
    img.paste(sym, (box[2] - 230, box[3] - 120), sym)
    _sparkle(d, box[2] - 250, box[3] - 90, 22, CHEEK)
    _corner_logo(img, on_color=False)
    return _png(img)


# ---------- D. 숫자 한 방(바이브 코딩 기록) ----------

def render_number(ep: dict) -> bytes:
    img = Image.new("RGB", (W, H), LAVENDER)
    d = ImageDraw.Draw(img)
    fl = _font("Bold", 64)
    label = _plain(ep.get("label") or "이번 주 커밋")
    d.text(((W - d.textlength(label, font=fl)) // 2, 250), label, font=fl, fill=INK)
    num = str(ep["number"])
    fn = _title_font(420 if len(num) <= 2 else 330)
    d.text(((W - d.textlength(num, font=fn)) // 2, 330), num, font=fn, fill=WHITE, stroke_width=6, stroke_fill=INK)
    y = _lines(d, X0, 860, ep["line1"], _title_font(84), W - 2 * X0, 1, INK, center=True)
    _lines(d, X0, y + 10, ep["line2"], _title_font(84), W - 2 * X0, 1, INK, center=True)
    _sparkle(d, 190, 430, 40, CHEEK)
    _sparkle(d, 890, 720, 30, WHITE)
    _corner_logo(img, on_color=False)
    return _png(img)


def render_episode(ep: dict, images: dict | None = None) -> list[bytes]:
    """앱 에피소드 한 장(PNG 목록 하나짜리 — 게시 쪽은 장수로 피드/캐러셀을 고름)."""
    images = images or {}
    if ep["angle"] == "vibe":
        return [render_number(ep)]
    color = theme_color(ep.get("color"), images.get("icon"))
    if ep["angle"] == "new":
        return [render_memo(ep, color, ep.get("date_label") or "")]
    return [render_impact(ep, color)]


# ---------- 게임 개발 일지: 화면 전 → 후 ----------

def render_game(info: dict, before, after) -> bytes:
    """after(오늘 화면)는 꼭 있음. before가 있으면 위(전)·아래(후), 없으면 오늘 화면 한 장 크게."""
    img = Image.new("RGB", (W, H), INK)
    d = ImageDraw.Draw(img)
    x = _pill(d, X0, 70, info["name"], _font("Bold", 38), LAVENDER)
    _pill(d, x + 16, 70, "화면 바뀜" if before is not None else "오늘 화면", _font("Bold", 38), CHEEK)
    top, bottom = 170, H - 130
    if before is not None:
        mid = (top + bottom) // 2
        _picture(img, d, before, (X0, top + 10, W - X0 - SHADOW, mid - 30))
        _picture(img, d, after, (X0, mid + 30, W - X0 - SHADOW, bottom))
        fb = _font("Black", 40)
        _pill(d, X0 + 20, top + 30, "전", fb, WHITE, pad=(20, 6))
        _pill(d, X0 + 20, mid + 50, "후", fb, LAVENDER, pad=(20, 6))
    else:
        _picture(img, d, after, (X0, top + 10, W - X0 - SHADOW, bottom))
    d.text((X0, H - 92), "@itssophie.dev · 게임 개발 일지", font=_font("Medium", 30), fill=(200, 196, 206))
    logo = _logo(40)
    d.rounded_rectangle([W - X0 - logo.width - 28, H - 104, W - X0, H - 44], radius=30, fill=WHITE)
    img.paste(logo, (W - X0 - logo.width - 14, H - 94), logo)
    return _png(img)
