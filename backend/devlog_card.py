"""주간 개발 에피소드 캐러셀(1080x1350, 4:5) — 앱 하나 집중, 소피앱스 브랜드 톤.

1 훅 → 2 이 앱은요(소개 + 대표 화면) → 3 이야기(소재에 따라 제목·칸 이름이 다름, 캡처가 있으면 같이)
→ 4 그래서 → 5 써 보기. 소재(ep["angle"]): story(앱 이야기) / new(새로 시작한 앱) / vibe(바이브 코딩 기록 —
2장은 이번 주 만진 앱 목록, 5장은 소피앱스 전체).
크림 종이 배경 + 굵은 잉크 외곽선 + 스티커 그림자(오프셋 그림자, 그라데이션 없음) + 라벤더/볼터치 포인트.
로고는 assets/brand의 원본 PNG를 그대로 씀(다시 그리지 않음).
한글 제목은 브랜드 글꼴 Jua(SOCIAL_FONT_DIR에 Jua-Regular.ttf가 있으면), 없으면 Noto Sans CJK Black.
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
SOFT = (120, 114, 128)
OUTLINE = 5
SHADOW = 10
PAGES = 5
X0 = 72

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
    out = "".join(ch for ch in str(text or "")
                  if ord(ch) < 0x2190 or 0x3000 <= ord(ch) <= 0xD7FF or 0xFF00 <= ord(ch) <= 0xFFEF)
    return " ".join(out.split())


def _wrap(d: ImageDraw.ImageDraw, text: str, font, max_w: int, max_lines: int) -> list[str]:
    """띄어쓰기 단위로 줄바꿈(단어가 중간에 잘리거나 '?'만 혼자 남지 않게). 한 단어가 한 줄보다 길면
    그 단어만 글자 단위로 자름. 넘치면 마지막 줄 말줄임."""
    lines, cur = [], ""
    for word in _plain(text).split(" "):
        cand = f"{cur} {word}" if cur else word
        if d.textlength(cand, font=font) <= max_w:
            cur = cand
            continue
        if cur:
            lines.append(cur)
        cur = ""
        for ch in word:  # 한 줄에 안 들어가는 긴 단어
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


def _text(d, xy, text, font, max_w, max_lines, line_h, fill=INK) -> int:
    """줄바꿈해서 쓰고 다음 y를 돌려줌."""
    x, y = xy
    for ln in _wrap(d, text, font, max_w, max_lines):
        d.text((x, y), ln, font=font, fill=fill)
        y += line_h
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


def _picture(img: Image.Image, d: ImageDraw.ImageDraw, pic: Image.Image, box, radius=32) -> None:
    """그림을 box 안에 비율 유지로 맞추고, 실제 크기에 맞춘 스티커 테두리를 둘러 붙임(가운데 정렬)."""
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


def _base(page: int, label: str) -> tuple[Image.Image, ImageDraw.ImageDraw]:
    img = Image.new("RGB", (W, H), PAPER)
    d = ImageDraw.Draw(img)
    logo = _logo(54)
    img.paste(logo, (X0, 64), logo)
    f = _font("Bold", 30)
    pg = f"{page}/{PAGES}"
    d.text((W - X0 - d.textlength(pg, font=f), 74), pg, font=f, fill=SOFT)
    if label:
        _pill(d, X0, 170, label, _font("Bold", 34), LAVENDER)
    d.text((X0, H - 92), "@itssophie.dev · 만드는 과정 공개", font=_font("Medium", 30), fill=SOFT)
    return img, d


def _png(img: Image.Image) -> bytes:
    buf = io.BytesIO()
    img.save(buf, "PNG", optimize=True)
    return buf.getvalue()


def _app_badge(img, d, ep, icon, x, y, size=72) -> int:
    """아이콘(있으면) + 앱 이름 칩. 끝 x를 돌려줌."""
    if icon is not None:
        _picture(img, d, icon, (x, y, x + size, y + size), radius=18)
        x += size + 22
    return _pill(d, x, y + (size - 56) // 2, ep["name"], _font("Bold", 36), PAPER)


def slide_hook(ep: dict, icon) -> bytes:
    img, d = _base(1, f"BUILD LOG · {ep['span']}")
    sym = _logo(150, symbol=True)
    img.paste(sym, (W - X0 - 150, 150), sym)
    _sparkle(d, W - 260, 175, 22, CHEEK)
    _sparkle(d, W - 60, 300, 16, LAVENDER)

    y = _text(d, (X0, 360), ep["hook"], _title_font(108), W - 2 * X0, 3, 132)
    _app_badge(img, d, ep, icon, X0, y + 50)
    _text(d, (X0, y + 160), ep["tagline"], _font("Regular", 40), W - 2 * X0, 2, 56, fill=SOFT)
    f = _font("Bold", 34)
    hint = "넘겨서 보기 →"
    d.text((W - X0 - d.textlength(hint, font=f), H - 96), hint, font=f, fill=LAVENDER_INK)
    return _png(img)


def slide_apps(ep: dict) -> bytes:
    """바이브 코딩 기록의 2장: 이번 주 만진 앱들(이름 + 한 줄 소개 + 커밋 수)."""
    img, d = _base(2, "이번 주 만진 것들")
    y = 280
    fn, ft = _font("Bold", 44), _font("Regular", 34)
    for a in ep["apps"][:4]:
        lines = _wrap(d, a["tagline"], ft, W - 2 * X0 - 100 - SHADOW, 2)
        box = (X0, y, W - X0 - SHADOW, y + 96 + len(lines) * 48)
        _sticker(d, box, WHITE, radius=24)
        d.text((X0 + 40, y + 26), _plain(a["name"]), font=fn, fill=INK)
        cnt = f"커밋 {a['count']}번"
        fc = _font("Bold", 32)
        d.text((box[2] - 40 - d.textlength(cnt, font=fc), y + 34), cnt, font=fc, fill=LAVENDER_INK)
        for i, ln in enumerate(lines):
            d.text((X0 + 40, y + 86 + i * 48), ln, font=ft, fill=SOFT)
        y = box[3] + 34
        if y > H - 260:
            break
    return _png(img)


def slide_about(ep: dict, icon, shot) -> bytes:
    if ep.get("angle") == "vibe":
        return slide_apps(ep)
    img, d = _base(2, "새로 만드는 앱" if ep.get("angle") == "new" else "이 앱은요")
    x = X0
    if icon is not None:
        _picture(img, d, icon, (X0, 270, X0 + 110, 380), radius=26)
        x = X0 + 140
    _text(d, (x, 278), ep["name"], _title_font(88), W - x - X0, 1, 100)
    y = _text(d, (X0, 420), ep["tagline"], _font("Medium", 42), W - 2 * X0, 3, 60)
    if shot is not None:
        _picture(img, d, shot, (X0 + 40, y + 50, W - X0 - 40 - SHADOW, H - 150))
    else:  # 화면이 아직 없는 앱: 몬스터 스티커로
        sym = _logo(360, symbol=True)
        img.paste(sym, ((W - 360) // 2, y + 140), sym)
        _sparkle(d, W // 2 - 230, y + 190, 30, CHEEK)
        _sparkle(d, W // 2 + 220, y + 420, 24, LAVENDER)
        f = _font("Bold", 36)
        msg = "화면은 곧 공개할게요"
        d.text(((W - d.textlength(msg, font=f)) // 2, y + 560), msg, font=f, fill=SOFT)
    return _png(img)


def _labeled(d, y, tag, tag_fill, text, font, max_lines) -> int:
    _pill(d, X0, y, tag, _font("Bold", 30), tag_fill, pad=(18, 8))
    return _text(d, (X0, y + 76), text, font, W - 2 * X0, max_lines, int(font.size * 1.38)) + 30


def _points(d, y, points) -> int:
    fp = _font("Bold", 40)
    for pt in points[:3]:
        d.ellipse([X0 + 8, y + 12, X0 + 36, y + 40], fill=LAVENDER, outline=INK, width=4)
        y = _text(d, (X0 + 62, y), pt, fp, W - 2 * X0 - 62, 2, 56) + 26
    return y


def slide_change(ep: dict, capture) -> bytes:
    """이야기 두 칸(소재마다 이름이 다름). 핵심 목록(points)은 4장에서 보여 주니 여기선 이야기와 (있으면) 캡처만."""
    img, d = _base(3, ep.get("section") or "이번 주 바꾼 것")
    shot = capture is not None
    f = _font("Medium", 42 if shot else 48)
    labels = ep.get("labels") or ["불편했던 점", "그래서"]
    y = 290
    if ep.get("part1"):
        y = _labeled(d, y, labels[0], CHEEK, ep["part1"], f, 2 if shot else 4) + (0 if shot else 30)
    if ep.get("part2"):
        y = _labeled(d, y, labels[1], LAVENDER, ep["part2"], f, 2 if shot else 5)
    if shot:
        _picture(img, d, capture, (X0 + 40, y + 20, W - X0 - 40 - SHADOW, H - 150))
    else:
        _sparkle(d, W - 130, H - 230, 30, CHEEK)
        _sparkle(d, W - 210, H - 170, 20, LAVENDER)
    return _png(img)


def slide_result(ep: dict) -> bytes:
    img, d = _base(4, "그래서 이렇게")
    y = 290
    if ep.get("result"):
        fs = _font("Medium", 44)
        lines = _wrap(d, ep["result"], fs, W - 2 * X0 - 100 - SHADOW, 4)
        box = (X0, y, W - X0 - SHADOW, y + 70 + len(lines) * 64)
        _sticker(d, box, WHITE)
        for i, ln in enumerate(lines):
            d.text((X0 + 50, y + 36 + i * 64), ln, font=fs, fill=INK)
        y = box[3] + 70
    y = _points(d, y, ep["points"])
    yy = max(y + 40, H - 330)
    if ep.get("count"):
        fn = _title_font(84)
        num = str(ep["count"])
        unit = "번 커밋한 한 주" if ep.get("angle") == "vibe" else "번 고친 한 주"
        d.text((X0, yy), num, font=fn, fill=LAVENDER_INK)
        d.text((X0 + d.textlength(num, font=fn) + 8, yy + 34), unit, font=_font("Bold", 42), fill=INK)
    _sparkle(d, W - 120, yy + 40, 26, CHEEK)
    return _png(img)


def slide_try(ep: dict, icon) -> bytes:
    if ep.get("angle") == "vibe":  # 앱 하나가 아니라 소피앱스 전체로
        ep = {**ep, "name": "소피앱스", "tagline": "혼자 바이브 코딩으로 만드는 작은 앱과 게임들", "others": []}
        icon = None
    img, d = _base(5, "")
    if icon is not None:
        _picture(img, d, icon, ((W - 260) // 2, 230, (W + 260) // 2, 490), radius=56)
    else:
        sym = _logo(260, symbol=True)
        img.paste(sym, ((W - 260) // 2, 230), sym)
    _sparkle(d, W // 2 - 200, 260, 28, CHEEK)
    _sparkle(d, W // 2 + 190, 470, 22, LAVENDER)
    ft = _title_font(96)
    name = _plain(ep["name"])
    d.text(((W - d.textlength(name, font=ft)) // 2, 540), name, font=ft, fill=INK)
    fs = _font("Medium", 40)
    y = 680
    for ln in _wrap(d, ep["tagline"], fs, W - 2 * X0 - 40, 2):
        d.text(((W - d.textlength(ln, font=fs)) // 2, y), ln, font=fs, fill=INK)
        y += 58
    fb = _font("Bold", 46)
    cta = "프로필 링크에서 만나 보세요"
    bw = d.textlength(cta, font=fb) + 100
    box = (int((W - bw) // 2), y + 60, int((W + bw) // 2), y + 60 + 110)
    _sticker(d, box, LAVENDER, radius=55)
    d.text(((W - d.textlength(cta, font=fb)) // 2, box[1] + 28), cta, font=fb, fill=INK)
    if ep.get("others"):
        fo = _font("Regular", 34)
        other = "이번 주엔 " + ", ".join(_plain(o) for o in ep["others"]) + "도 만졌어요"
        for i, ln in enumerate(_wrap(d, other, fo, W - 2 * X0, 2)):
            d.text(((W - d.textlength(ln, font=fo)) // 2, box[3] + 70 + i * 48), ln, font=fo, fill=SOFT)
    return _png(img)


def render_episode(ep: dict, images: dict | None = None) -> list[bytes]:
    """5장 PNG. images: {"icon", "shot", "capture"} PIL 이미지(없으면 None)."""
    images = images or {}
    icon, shot, capture = images.get("icon"), images.get("shot"), images.get("capture")
    return [slide_hook(ep, icon), slide_about(ep, icon, shot), slide_change(ep, capture),
            slide_result(ep), slide_try(ep, icon)]
