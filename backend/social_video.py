"""이슈팝 릴스/스레드용 세로 영상(1080x1920, 9:16) 렌더러.

구성(약 13.5초): 인트로 → 5위부터 1위까지 카운트다운 → 아웃트로.
Pillow로 프레임을 그려 ffmpeg(libx264)로 인코딩한다. 음악은 넣지 않는다
(API 게시로는 인스타그램 라이선스 음원을 붙일 수 없음).
"""
from __future__ import annotations

import subprocess
from datetime import datetime
from zoneinfo import ZoneInfo

from PIL import Image, ImageDraw

from social_card import (INK, INK_SOFT, NAVY, NAVY_SOFT, PAPER, WEEKDAYS, WHITE, YELLOW,
                         _fit, _font, _keyword)

W, H, FPS = 1080, 1920, 30
INTRO, PER_RANK, OUTRO = 2.2, 1.9, 2.4
SOFT_TXT = (205, 214, 232)


def _ease(t: float) -> float:
    t = max(0.0, min(1.0, t))
    return 1 - (1 - t) ** 3


def _bg() -> Image.Image:
    img = Image.new("RGB", (W, H), NAVY)
    deco = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    dd = ImageDraw.Draw(deco)
    dd.polygon([(700, 160), (1160, 90), (1220, 900), (780, 960)], fill=NAVY_SOFT + (110,))
    dd.polygon([(-120, 1380), (360, 1320), (420, 2000), (-60, 2060)], fill=NAVY_SOFT + (80,))
    img.paste(deco, (0, 0), deco)
    d = ImageDraw.Draw(img)
    f = _font("Black", 44)
    d.text((80, 110), "Issue", font=f, fill=WHITE)
    x = 80 + d.textlength("Issue ", font=f)
    d.text((x, 110), "Pop", font=f, fill=WHITE)
    d.rounded_rectangle([x, 168, x + d.textlength("Pop", font=f), 176], radius=4, fill=YELLOW)
    return img


def _layer() -> tuple[Image.Image, ImageDraw.ImageDraw]:
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    return im, ImageDraw.Draw(im)


def _intro(now: datetime) -> Image.Image:
    im, d = _layer()
    f = _font("Black", 104)
    d.text((80, 640), "오늘 가장 많이", font=f, fill=WHITE)
    hl = "보도된 이슈"
    w = d.textlength(hl, font=f)
    d.rounded_rectangle([70, 780, 70 + w + 30, 912], radius=18, fill=YELLOW)
    d.text((85, 776), hl, font=f, fill=INK)
    d.text((80, 930), "TOP 5", font=_font("Black", 150), fill=WHITE)
    d.text((86, 1140), f"{now.month}월 {now.day}일 ({WEEKDAYS[now.weekday()]}) {now.hour:02d}:{now.minute:02d} 기준",
           font=_font("Medium", 44), fill=SOFT_TXT)
    return im


def _rank(rank: int, it: dict) -> Image.Image:
    im, d = _layer()
    d.text((80, 470), f"{rank}위", font=_font("Black", 200), fill=YELLOW if rank == 1 else WHITE)

    x0, y0, x1, y1 = 60, 780, W - 60, 1460
    d.rounded_rectangle([x0 + 12, y0 + 16, x1 + 12, y1 + 16], radius=36, fill=(0, 0, 0, 70))
    d.rounded_rectangle([x0, y0, x1, y1], radius=36, fill=PAPER)

    cat = it.get("category", "")
    fc = _font("Bold", 40)
    cw = d.textlength(cat, font=fc)
    d.rounded_rectangle([x0 + 60, y0 + 60, x0 + 60 + cw + 36, y0 + 120], radius=12, fill=(232, 236, 244))
    d.text((x0 + 78, y0 + 60), cat, font=fc, fill=NAVY)

    fk = _font("Black", 124)
    kw = _fit(d, _keyword(it), fk, x1 - x0 - 120)
    kw_w = d.textlength(kw, font=fk)
    if rank == 1:
        d.rounded_rectangle([x0 + 50, y0 + 250, x0 + 70 + kw_w, y0 + 300], radius=8, fill=YELLOW)
    d.text((x0 + 60, y0 + 140), kw, font=fk, fill=INK)

    ft = _font("Regular", 40)
    title = it.get("representative_title", "")
    # 두 줄까지 줄바꿈
    lines, cur = [], ""
    for ch in title:
        if d.textlength(cur + ch, font=ft) > x1 - x0 - 120:
            lines.append(cur)
            cur = ch
        else:
            cur += ch
    lines.append(cur)
    if len(lines) > 2:
        lines = [lines[0], _fit(d, lines[1] + "".join(lines[2:]), ft, x1 - x0 - 120)]
    for i, ln in enumerate(lines):
        d.text((x0 + 60, y0 + 340 + i * 58), ln, font=ft, fill=INK_SOFT)

    fs = _font("Black", 64)
    fu = _font("Bold", 40)
    sx = x0 + 60
    for num, unit in ((str(it.get("outlet_count", 0)), "개 매체"), (str(it.get("article_count", 0)), "건 보도")):
        d.text((sx, y0 + 500), num, font=fs, fill=NAVY)
        sx += d.textlength(num, font=fs) + 6
        d.text((sx, y0 + 522), unit, font=fu, fill=NAVY)
        sx += d.textlength(unit, font=fu) + 50
    return im


def _outro() -> Image.Image:
    im, d = _layer()
    f = _font("Black", 88)
    d.text((80, 720), "전체 이슈와", font=f, fill=WHITE)
    d.text((80, 830), "매체별 기사는", font=f, fill=WHITE)
    w = d.textlength("앱에서", font=f)
    d.rounded_rectangle([70, 950, 70 + w + 30, 1066], radius=16, fill=YELLOW)
    d.text((85, 942), "앱에서", font=f, fill=INK)
    d.text((80, 1160), "Google Play에서 ‘이슈팝’ 검색", font=_font("Bold", 50), fill=YELLOW)
    return im


def _compose(bg: Image.Image, layer: Image.Image, t_in: float, t_out: float) -> Image.Image:
    """t_in: 등장 진행(0→1), t_out: 퇴장 진행(0→1)."""
    a = _ease(t_in) * (1 - _ease(t_out))
    dx = int((1 - _ease(t_in)) * 160 - _ease(t_out) * 160)
    frame = bg.copy()
    lay = layer
    if a < 1:
        alpha = lay.getchannel("A").point(lambda v: int(v * a))
        lay = lay.copy()
        lay.putalpha(alpha)
    frame.paste(lay, (dx, 0), lay)
    return frame


def render_video(issues: list[dict], out_path: str, now: datetime | None = None, top_n: int = 5) -> str:
    now = now or datetime.now(ZoneInfo("Asia/Seoul"))
    issues = issues[:top_n]
    bg = _bg()
    segments = [(_intro(now), INTRO)]
    for r in range(len(issues), 0, -1):
        segments.append((_rank(r, issues[r - 1]), PER_RANK))
    segments.append((_outro(), OUTRO))

    proc = subprocess.Popen(
        ["ffmpeg", "-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}",
         "-r", str(FPS), "-i", "-", "-f", "lavfi", "-i", "anullsrc=r=44100:cl=stereo", "-shortest",
         "-c:v", "libx264", "-preset", "veryfast", "-crf", "20", "-pix_fmt", "yuv420p",
         "-c:a", "aac", "-b:a", "128k", "-movflags", "+faststart", out_path],
        stdin=subprocess.PIPE,
    )
    fade = 0.35
    for idx, (layer, dur) in enumerate(segments):
        n = int(dur * FPS)
        last = idx == len(segments) - 1
        still: bytes | None = None  # 등장·퇴장 사이의 멈춘 구간은 같은 프레임이라 한 번만 그림(1 OCPU 서버 부담 줄이기)
        for f in range(n):
            t = f / FPS
            t_in = t / fade
            t_out = 0.0 if last else max(0.0, (t - (dur - fade)) / fade)
            if t_in >= 1 and t_out == 0:
                if still is None:
                    still = _compose(bg, layer, 1.0, 0.0).tobytes()
                proc.stdin.write(still)
            else:
                proc.stdin.write(_compose(bg, layer, t_in, t_out).tobytes())
    proc.stdin.close()
    if proc.wait() != 0:
        raise RuntimeError("ffmpeg 인코딩 실패")
    return out_path
