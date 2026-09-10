import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';

import '../models/issue.dart';
import '../theme.dart';

/// 2026-09-09: "오늘의 트렌드 공유 카드" — 화면이 아니라 상단바 버튼 하나로,
/// 상위 이슈 랭킹을 이미지 카드로 만들어 OS 공유 시트로 넘김(카카오톡/
/// 인스타 스토리 등). [_ShareCard]를 실제 화면 밖(왼쪽으로 9999px)에
/// 잠깐 그렸다가 RepaintBoundary로 캡처만 하고 바로 치움 — 사용자 눈에
/// 보이는 카드가 아니라 이미지 생성용 임시 렌더링임.
Future<void> shareTodayTrend(BuildContext context, List<IssueSummary> issues) async {
  final top = issues.take(5).toList();
  if (top.isEmpty) return;

  final boundaryKey = GlobalKey();
  final overlay = Overlay.of(context);
  final entry = OverlayEntry(
    builder: (_) => Positioned(
      left: -9999,
      top: 0,
      child: Material(
        color: Colors.transparent,
        child: RepaintBoundary(key: boundaryKey, child: _ShareCard(issues: top)),
      ),
    ),
  );
  overlay.insert(entry);

  try {
    // 삽입 직후엔 아직 레이아웃/페인트가 안 끝났을 수 있어서(빈 이미지가
    // 캡처되는 경우가 있었음) 프레임을 두 번 기다려줌.
    await WidgetsBinding.instance.endOfFrame;
    await WidgetsBinding.instance.endOfFrame;

    final boundary = boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2.5);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final bytes = byteData!.buffer.asUint8List();

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(bytes, name: 'issue-pop-trend.png', mimeType: 'image/png')],
        text: '오늘의 이슈판 트렌드',
      ),
    );
  } finally {
    entry.remove();
  }
}

// 2026-09-09: 색 테마 프리셋이 생기면서 AppColors.ink/bg가 다크 프리셋에서는
// 뒤집힘(ink가 밝은색, bg가 어두운색) — 공유 카드는 인스타 스토리 등에
// 올라가는 고정된 브랜드 자산이라 앱 테마와 무관하게 항상 같은 모습이어야
// 해서, 여기서만 고정 색을 씀(현재 프리셋의 ink/accent2/bg 값 그대로).
const _shareCardBg = Color(0xFF232A20);
const _shareCardFg = Color(0xFFEEF1EA);
const _shareCardAccent = Color(0xFFA14B2A);

class _ShareCard extends StatelessWidget {
  const _ShareCard({required this.issues});

  final List<IssueSummary> issues;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Container(
      width: 320,
      padding: const EdgeInsets.all(20),
      color: _shareCardBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Issue Pop · ${now.month}월 ${now.day}일',
            style: AppTypography.serif(fontSize: 18, fontWeight: FontWeight.w700, color: _shareCardFg),
          ),
          const SizedBox(height: 3),
          Text(
            '오늘 가장 많이 보도된 이슈',
            style: TextStyle(fontSize: 11.5, color: _shareCardFg.withValues(alpha: 0.6)),
          ),
          const SizedBox(height: 18),
          for (var i = 0; i < issues.length; i++)
            Padding(
              padding: EdgeInsets.only(bottom: i == issues.length - 1 ? 0 : 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 18,
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _shareCardAccent),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 카드에서처럼 대표 키워드 하나만으론 무슨 뉴스인지
                        // 잘 안 보인다는 피드백으로 보조 키워드도 같이 씀
                        // (expandable_issue_card.dart와 같은 표기: "A · B").
                        Text.rich(
                          TextSpan(children: [
                            TextSpan(
                              text: issues[i].keyword,
                              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: _shareCardFg),
                            ),
                            if (issues[i].keywords.length > 1) ...[
                              TextSpan(text: ' · ', style: TextStyle(color: _shareCardFg.withValues(alpha: 0.5))),
                              TextSpan(
                                text: issues[i].keywords[1],
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: _shareCardFg.withValues(alpha: 0.75),
                                ),
                              ),
                            ],
                          ]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          issues[i].representativeTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 10.5, color: _shareCardFg.withValues(alpha: 0.55), height: 1.3),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 18),
          Text('issue-pop.com', style: TextStyle(fontSize: 10, color: _shareCardFg.withValues(alpha: 0.4))),
        ],
      ),
    );
  }
}
