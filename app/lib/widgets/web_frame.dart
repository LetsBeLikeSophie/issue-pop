// ignore_for_file: prefer_const_constructors_in_immutables
// (이 파일의 일부 위젯은 일부러 const로 만들지 않음 — const 위젯은 테마가 바뀌어도 다시 안 그려져서 옛 색이 남았음)
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api_client.dart' show OutletStat, WordEntry, WordOfDay;
import '../models/promo.dart';
import '../theme.dart';
import '../theme_store.dart';
import 'embed_view.dart';

/// 2026-10-27: 웹(넓은 화면)에서 앱을 폰 폭의 프레임으로 가운데 고정하고 양옆에 소개·홍보 카드를 보여주는 틀.
/// 가로로 넓은 화면에 앱이 그대로 퍼져 보이던 걸 "폰 화면"처럼 보이게 하려는 것. 좁은 화면(폰 브라우저)이나 앱에서는
/// 아무것도 안 하고 [child]를 그대로 보여줌.
///
/// 양옆 카드는 서버(GET /promos, backend/promos.json)에서 받아서 앱을 다시 올리지 않고 바꿈 — [promosLoader]가 실패하면
/// [kDefaultPromos](Buy Me a Coffee)로 대체함.
class WebFrame extends StatefulWidget {
  const WebFrame({
    super.key,
    required this.child,
    this.promosLoader,
    this.statsLoader,
    this.wordLoader,
    this.outletsLoader,
    this.wordHistoryLoader,
    this.enabled = kIsWeb,
  });

  final Widget child;
  final Future<List<PromoCard>> Function()? promosLoader;

  /// 왼쪽 칸의 "오늘의 숫자"(이슈·기사 수)와 "오늘의 단어" 카드용. 못 받으면 그 카드만 안 보임.
  final Future<({int issueCount, int articleCount})> Function()? statsLoader;
  final Future<WordOfDay> Function()? wordLoader;

  /// 왼쪽 칸의 "언론사별 기사 수" 차트용(언론사 이름을 누르면 그 언론사 홈페이지).
  final Future<List<OutletStat>> Function()? outletsLoader;

  /// 지난 오늘의 단어(최신순). 받으면 오늘의 단어 카드가 좌우로 넘겨 보는 카드가 되고, 못 받으면 [wordLoader]의 오늘 단어만 보임.
  final Future<List<WordEntry>> Function()? wordHistoryLoader;

  /// 기본은 웹일 때만(테스트에서 켜고 끌 수 있게 분리).
  final bool enabled;

  /// 이 폭 미만이면 프레임 없이 앱을 꽉 차게 보여줌(폰 브라우저).
  static const frameMinWidth = 720.0;

  /// 이 폭 이상이면 양옆 칸도 보여줌(프레임 446 + 양옆 칸 2×340 + 간격 72 = 1198보다 커야 넘치지 않음).
  static const panelsMinWidth = 1240.0;

  /// 테스트용: 웹이 아닌 환경에서도 임베드 카드(펼치기 버튼)를 보이게 함.
  @visibleForTesting
  static bool debugAssumeEmbeddable = false;

  static const frameWidth = 430.0;
  static const panelWidth = 340.0;

  @override
  State<WebFrame> createState() => _WebFrameState();
}

class _WebFrameState extends State<WebFrame> {
  late final Future<List<PromoCard>> _promos = _load();
  late final Future<({int issueCount, int articleCount})?> _stats = _safe(widget.statsLoader);
  late final Future<WordOfDay?> _word = _safe(widget.wordLoader);
  late final Future<List<OutletStat>?> _outlets = _safe(widget.outletsLoader);
  late final Future<List<WordEntry>?> _wordHistory = _safe(widget.wordHistoryLoader);

  Future<List<PromoCard>> _load() async {
    final loader = widget.promosLoader;
    if (loader == null) return kDefaultPromos;
    try {
      final cards = await loader();
      return cards.isEmpty ? kDefaultPromos : cards;
    } catch (_) {
      return kDefaultPromos;
    }
  }

  /// 부가 카드(숫자·단어)는 실패해도 그 카드만 숨김.
  Future<T?> _safe<T>(Future<T> Function()? loader) async {
    if (loader == null) return null;
    try {
      return await loader();
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth < WebFrame.frameMinWidth) return widget.child;
        final showPanels = c.maxWidth >= WebFrame.panelsMinWidth;
        // 위아래 여백(28씩)을 두고, 너무 길어지지 않게 상한을 둠.
        final frameHeight = math.max(480.0, math.min(c.maxHeight - 56, 960.0));
        final media = MediaQuery.of(context);
        // Material이 있어야 양옆 칸의 글씨가 앱 글꼴(Noto Sans KR)과 기본 글자 스타일을 받음. MaterialApp.builder는 Scaffold 바깥이라
        // 이게 없으면 Flutter 기본 스타일(노란 밑줄이 형광펜처럼 보이고 글꼴이 달라짐)로 그려졌음.
        return Material(
          type: MaterialType.transparency,
          child: ColoredBox(
            color: AppColors.bg,
            child: Center(
            child: FutureBuilder<List<PromoCard>>(
              future: _promos,
              initialData: const <PromoCard>[],
              builder: (context, snapshot) {
                final promos = snapshot.data ?? const <PromoCard>[];
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (showPanels) ...[
                      SizedBox(
                        width: WebFrame.panelWidth,
                        height: frameHeight,
                        child: _SidePanel(
                          alignEnd: true,
                          cards: promos.where((p) => p.left).toList(),
                          header: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _BrandBlock(),
                              FutureBuilder<({int issueCount, int articleCount})?>(
                                future: _stats,
                                builder: (context, snap) {
                                  final stats = snap.data;
                                  if (stats == null) return const SizedBox.shrink();
                                  return Padding(padding: const EdgeInsets.only(top: 14), child: _StatsCard(stats: stats));
                                },
                              ),
                              FutureBuilder<List<OutletStat>?>(
                                future: _outlets,
                                builder: (context, snap) {
                                  final rows = snap.data;
                                  if (rows == null || rows.isEmpty) return const SizedBox.shrink();
                                  return Padding(padding: const EdgeInsets.only(top: 14), child: _OutletChartCard(rows: rows));
                                },
                              ),
                            ],
                          ),
                          footer: _Footer(),
                        ),
                      ),
                      const SizedBox(width: 36),
                    ],
                    _PhoneFrame(
                      width: WebFrame.frameWidth,
                      height: frameHeight,
                      media: media,
                      child: widget.child,
                    ),
                    if (showPanels) ...[
                      const SizedBox(width: 36),
                      SizedBox(
                        width: WebFrame.panelWidth,
                        height: frameHeight,
                        child: _SidePanel(
                          alignEnd: false,
                          cards: promos.where((p) => !p.left).toList(),
                          header: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _ThemePickerCard(),
                              FutureBuilder<List<WordEntry>?>(
                                future: _wordHistory,
                                builder: (context, historySnap) {
                                  final history = historySnap.data;
                                  if (history != null && history.isNotEmpty) {
                                    return Padding(padding: const EdgeInsets.only(top: 14), child: _WordCarouselCard(entries: history));
                                  }
                                  // 지난 단어 목록을 못 받았으면 오늘 단어 한 장만
                                  return FutureBuilder<WordOfDay?>(
                                    future: _word,
                                    builder: (context, snap) {
                                      final word = snap.data;
                                      if (word?.word == null) return const SizedBox.shrink();
                                      return Padding(padding: const EdgeInsets.only(top: 14), child: _WordCard(word: word!));
                                    },
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
            ),
          ),
        );
      },
    );
  }
}

/// 화면 전체를 다시 그리게 함 — 테마를 바꾼 직후 이미 열려 있는 화면(홈 목록 등)이 새 색으로 바뀌게(Flutter 공식 문서의 "rebuild all children"
/// 방식). AppColors는 Theme.of처럼 의존 관계를 만들지 않아서 MaterialApp이 다시 그려져도 const·캐시된 하위 위젯은 옛 색 그대로였음.
void _rebuildAll() {
  void rebuild(Element element) {
    element.markNeedsBuild();
    element.visitChildren(rebuild);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(rebuild);
}

/// 폰 모양 테두리 안에 앱을 넣음. 앱이 화면 크기를 MediaQuery로 읽는 곳이 있어서, 프레임 안의 크기로 덮어씀.
class _PhoneFrame extends StatelessWidget {
  const _PhoneFrame({required this.width, required this.height, required this.media, required this.child});

  final double width;
  final double height;
  final MediaQueryData media;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width + 16,
      height: height + 16,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF15191B),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)), // 다크 배경에서도 폰 윤곽이 보이게
        borderRadius: BorderRadius.circular(40),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 32, offset: const Offset(0, 14))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: MediaQuery(
          data: media.copyWith(
            size: Size(width, height),
            padding: EdgeInsets.zero,
            viewPadding: EdgeInsets.zero,
            viewInsets: EdgeInsets.zero,
          ),
          child: child,
        ),
      ),
    );
  }
}

/// 양옆 칸의 글자 스타일 — 카드마다 제목 모양이 달라 정신없어 보이던 걸 하나로 맞춤. 세리프는 로고(Issue Pop)에만 쓰고
/// 나머지는 앱 기본 글꼴(Noto Sans KR). 카드 제목 13.5 굵게 / 본문 12.5 / 보조 11.5.
TextStyle _cardTitle() => TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.ink, height: 1.3);
TextStyle _cardBody() => TextStyle(fontSize: 12.5, color: AppColors.inkSoft, height: 1.55);
TextStyle _cardMeta() => TextStyle(fontSize: 11.5, color: AppColors.inkFaint, height: 1.4);

class _SidePanel extends StatelessWidget {
  const _SidePanel({required this.alignEnd, required this.cards, this.header, this.footer});

  final bool alignEnd;
  final List<PromoCard> cards;
  final Widget? header;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (header != null) ...[header!, const SizedBox(height: 14)],
                for (final card in cards) ...[_PromoCardView(card: card), const SizedBox(height: 14)],
              ],
            ),
          ),
        ),
        ?footer,
      ],
    );
  }
}

class _BrandBlock extends StatelessWidget {
  _BrandBlock();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Issue Pop', style: AppTypography.serif(fontSize: 34, fontWeight: FontWeight.w700, color: AppColors.ink)),
          const SizedBox(height: 10),
          Text('오늘 어떤 이슈가 많이 보도됐는지, 한눈에', style: _cardTitle().copyWith(fontSize: 14.5)),
          const SizedBox(height: 8),
          Text('여러 언론사의 기사를 모아 같은 이슈끼리 묶어 보여줘요. 알림과 홈 화면 위젯은 앱에서 쓸 수 있어요.', style: _cardBody()),
        ],
      ),
    );
  }
}

/// "오늘의 숫자" — 서버가 지금 모은 이슈·기사 수(앱 홈 위쪽에서 쓰는 /stats와 같은 값).
class _StatsCard extends StatelessWidget {
  const _StatsCard({required this.stats});

  final ({int issueCount, int articleCount}) stats;

  @override
  Widget build(BuildContext context) {
    return _InfoCard(
      label: '오늘의 숫자',
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '${stats.issueCount}',
              style: AppTypography.mono(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.accent),
            ),
            TextSpan(text: '개 이슈 · ', style: _cardBody()),
            TextSpan(
              text: '${stats.articleCount}',
              style: AppTypography.mono(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.accent),
            ),
            TextSpan(text: '건 기사', style: _cardBody()),
          ],
        ),
      ),
    );
  }
}

/// "언론사별 기사 수" — 지금(최근 약 30시간) 모인 기사가 언론사마다 몇 건인지를 가로 막대로 보여주고, 이름을 누르면 그 언론사
/// 홈페이지로 감. 막대 길이는 가장 많은 언론사를 기준으로 한 비율.
class _OutletChartCard extends StatelessWidget {
  const _OutletChartCard({required this.rows});

  final List<OutletStat> rows;

  @override
  Widget build(BuildContext context) {
    final maxCount = rows.fold<int>(1, (m, r) => math.max(m, r.count));
    return _InfoCard(
      label: '언론사별 기사 수',
      child: Column(
        children: [
          for (final row in rows) _OutletBarRow(row: row, maxCount: maxCount),
        ],
      ),
    );
  }
}

class _OutletBarRow extends StatelessWidget {
  const _OutletBarRow({required this.row, required this.maxCount});

  final OutletStat row;
  final int maxCount;

  @override
  Widget build(BuildContext context) {
    final homepage = row.homepage;
    final name = SizedBox(
      width: 78,
      child: Text(
        row.outlet,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          color: homepage == null ? AppColors.inkSoft : AppColors.accent,
          decoration: homepage == null ? null : TextDecoration.underline,
          decorationColor: AppColors.accent.withValues(alpha: 0.35),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          homepage == null
              ? name
              : InkWell(
                  onTap: () => launchUrl(Uri.parse(homepage), mode: LaunchMode.externalApplication),
                  child: name,
                ),
          const SizedBox(width: 8),
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) {
                // 0건이어도 자리가 보이게 얇은 점선 대신 아주 짧은 막대, 그 외엔 비율(최소 4px)
                final width = row.count == 0 ? 2.0 : math.max(4.0, c.maxWidth * row.count / maxCount);
                return Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    key: ValueKey('bar-${row.outlet}'),
                    width: width,
                    height: 8,
                    decoration: BoxDecoration(
                      color: row.count == 0 ? AppColors.line : AppColors.accent,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 32,
            child: Text(
              '${row.count}',
              textAlign: TextAlign.right,
              style: AppTypography.mono(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.ink),
            ),
          ),
        ],
      ),
    );
  }
}

/// "오늘의 단어" — 서버가 매일 하나 골라 두는 단어(GET /word-of-day)와 뜻풀이.
class _WordCard extends StatelessWidget {
  const _WordCard({required this.word});

  final WordOfDay word;

  @override
  Widget build(BuildContext context) {
    return _InfoCard(
      label: '오늘의 단어',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(word.word!, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.accent, height: 1.3)),
          if ((word.definition ?? '').isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(word.definition!, maxLines: 4, overflow: TextOverflow.ellipsis, style: _cardBody()),
          ],
        ],
      ),
    );
  }
}

/// "오늘의 단어" — 지난 단어(최근 30일)를 좌우로 넘겨 봄: 마우스/터치패드는 양옆 화살표, 터치는 스와이프. 첫 장이 오늘.
class _WordCarouselCard extends StatefulWidget {
  const _WordCarouselCard({required this.entries});

  final List<WordEntry> entries;

  @override
  State<_WordCarouselCard> createState() => _WordCarouselCardState();
}

class _WordCarouselCardState extends State<_WordCarouselCard> {
  final _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _go(int to) => _controller.animateToPage(to, duration: const Duration(milliseconds: 220), curve: Curves.easeOut);

  /// "2026-10-27" → "10월 27일", 첫 장(오늘)은 "오늘".
  String _dateLabel(int i) {
    if (i == 0) return '오늘';
    final parts = widget.entries[i].date.split('-');
    if (parts.length != 3) return widget.entries[i].date;
    return '${int.tryParse(parts[1]) ?? parts[1]}월 ${int.tryParse(parts[2]) ?? parts[2]}일';
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.entries;
    final last = entries.length - 1;
    return _InfoCard(
      label: '오늘의 단어',
      child: Column(
        children: [
          SizedBox(
            height: 92,
            child: PageView.builder(
              controller: _controller,
              itemCount: entries.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (context, i) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entries[i].word, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.accent, height: 1.3)),
                  if ((entries[i].definition ?? '').isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(entries[i].definition!, maxLines: 3, overflow: TextOverflow.ellipsis, style: _cardBody()),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              // 왼쪽 = 더 최근(오늘 쪽), 오른쪽 = 더 지난 날. 끝에서는 비활성.
              IconButton(
                tooltip: '더 최근 단어',
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                onPressed: _index > 0 ? () => _go(_index - 1) : null,
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(_dateLabel(_index), textAlign: TextAlign.center, style: _cardMeta()),
              ),
              IconButton(
                tooltip: '이전 단어',
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                onPressed: _index < last ? () => _go(_index + 1) : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: _cardTitle()),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  _Footer();

  @override
  Widget build(BuildContext context) {
    Widget link(String label, String url) => InkWell(
          onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
          child: Text(label, style: _cardMeta().copyWith(decoration: TextDecoration.underline)),
        );
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 12,
        runSpacing: 4,
        children: [
          link('개인정보처리방침', 'https://api.issue-pop.com/privacy'),
          link('콘텐츠 제외 요청', 'mailto:contact@issue-pop.com'),
        ],
      ),
    );
  }
}

class _PromoCardView extends StatefulWidget {
  const _PromoCardView({required this.card});

  final PromoCard card;

  @override
  State<_PromoCardView> createState() => _PromoCardViewState();
}

class _PromoCardViewState extends State<_PromoCardView> {
  /// 임베드 카드가 펼쳐져 있는지. 처음엔 접어 둠 — 후원 폼이 처음부터 다 보이면 부담스럽다는 의견이었고, 접어 두면 제3자(Buy Me a
  /// Coffee) 페이지도 눌러서 펼칠 때만 불러옴(방문만 해서는 그쪽으로 접속 정보가 안 감).
  bool _open = false;

  PromoCard get card => widget.card;

  /// 임베드는 Buy Me a Coffee 위젯 주소만 허용(서버 파일이 잘못돼도 엉뚱한 사이트가 안 붙게).
  bool get _embeddable {
    final host = Uri.tryParse(card.embed)?.host ?? '';
    return (canEmbed || WebFrame.debugAssumeEmbeddable) &&
        card.embed.isNotEmpty &&
        (host == 'buymeacoffee.com' || host.endsWith('.buymeacoffee.com'));
  }

  @override
  Widget build(BuildContext context) {
    void open() => launchUrl(Uri.parse(card.url), mode: LaunchMode.externalApplication);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: card.highlight ? AppColors.accent : AppColors.line, width: card.highlight ? 1.5 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(card.title, style: _cardTitle()),
          if (card.body.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(card.body, style: _cardBody()),
          ],
          if (card.image.isNotEmpty) ...[
            const SizedBox(height: 12),
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  card.image,
                  width: 180,
                  height: 180,
                  filterQuality: FilterQuality.none, // QR이 흐려지지 않게
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            ),
          ],
          if (_embeddable) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => setState(() => _open = !_open),
                style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
                icon: Icon(_open ? Icons.expand_less : Icons.expand_more, size: 18),
                label: Text(_open ? '접기' : '응원하기'),
              ),
            ),
            // 눌렀을 때만 위젯을 만들어(그때 제3자 페이지를 불러옴) 카드가 아래로 부드럽게 길어짐
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              alignment: Alignment.topCenter,
              child: _open
                  ? Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Column(
                        children: [
                          KeyedSubtree(
                            key: ValueKey('embed-${card.id}'),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: buildEmbed(card.embed, card.embedHeight),
                            ),
                          ),
                          if (card.hasButton)
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(onPressed: open, child: Text(card.button)),
                            ),
                        ],
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ] else if (card.hasButton) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: card.highlight
                  ? FilledButton(
                      onPressed: open,
                      style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
                      child: Text(card.button),
                    )
                  : OutlinedButton(onPressed: open, child: Text(card.button)),
            ),
          ],
        ],
      ),
    );
  }
}

/// 웹에는 설정 화면이 없어서(설정은 앱에서) 색 테마만 바로 고르게 둠.
class _ThemePickerCard extends StatelessWidget {
  _ThemePickerCard();

  static const _labels = {
    ColorPreset.current: '기본',
    ColorPreset.neutral: '화이트',
    ColorPreset.dark: '다크',
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('화면 색상', style: _cardTitle()),
          const SizedBox(height: 10),
          ListenableBuilder(
            listenable: ThemeStore.instance,
            builder: (context, _) {
              final current = ThemeStore.instance.preset;
              return Row(
                children: [
                  for (final preset in ColorPreset.values) ...[
                    Expanded(child: _swatch(preset, current == preset)),
                    if (preset != ColorPreset.values.last) const SizedBox(width: 6),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _swatch(ColorPreset preset, bool selected) {
    final (bg, accent, accent2) = AppColors.previewColors(preset);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () {
        ThemeStore.instance.setPreset(preset);
        WidgetsBinding.instance.addPostFrameCallback((_) => _rebuildAll());
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.accent : AppColors.chipBg,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: bg,
                shape: BoxShape.circle,
                border: Border.all(color: selected ? Colors.white : AppColors.line),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(width: 6, height: 6, decoration: BoxDecoration(color: accent, shape: BoxShape.circle)),
                  const SizedBox(width: 2),
                  Container(width: 6, height: 6, decoration: BoxDecoration(color: accent2, shape: BoxShape.circle)),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _labels[preset]!,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? Colors.white : AppColors.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
