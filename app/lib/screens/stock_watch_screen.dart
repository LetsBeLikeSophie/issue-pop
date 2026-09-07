import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api_client.dart';
import '../device_registry.dart';
import '../theme.dart';
import '../widgets/app_card.dart';

/// 2026-09-06: 관심 종목(브랜드) 뉴스. 저장한 이슈(Archive)와 같은 패턴 —
/// 홈 화면 피드에는 아무것도 안 섞고, 상단바 아이콘 하나로만 진입함(홈
/// 화면 코드에 남아있는 "큐레이션성 콘텐츠는 이 화면에 안 섞는다"는
/// 결론과 같은 이유).
class StockWatchScreen extends StatefulWidget {
  const StockWatchScreen({super.key, required this.api});

  final ApiClient api;

  @override
  State<StockWatchScreen> createState() => _StockWatchScreenState();
}

class _StockWatchScreenState extends State<StockWatchScreen> {
  late final DeviceRegistry _devices = DeviceRegistry(widget.api);
  Future<List<StockWatch>>? _watches;
  final _scrollController = ScrollController();
  bool _showScrollTop = false;

  /// 2026-09-07: 가격을 탭하면 달러/원화가 화면 전체에서 한 번에 바뀌는
  /// 토글("환율 계산까지는 힘든가... 원으로 보고 싶다"는 피드백으로 추가,
  /// 설정 화면까지 가는 대신 숫자 자체를 눌러서 바꾸는 쪽을 택함 — 러닝
  /// 앱에서 거리 탭하면 km/mile 바뀌는 것과 같은 패턴). 환율은 서버가
  /// 하루 단위로 캐싱해둔 걸 한 번만 받아옴(Frankfurter.app 기반).
  double? _usdKrwRate;
  bool _showKrw = false;

  void _toggleCurrency() {
    if (_usdKrwRate == null) return; // 환율을 아직 못 받아왔으면 토글해도 의미 없음
    setState(() => _showKrw = !_showKrw);
  }

  /// 티커 칩을 누르면 그 종목 카드로 스크롤 이동시키는 데 씀(칩이 많아지면
  /// 훑어보기 힘들다는 피드백으로 추가) — 티커별로 하나씩 유지, build()마다
  /// 새로 만들지 않고 없는 것만 채움(같은 키 인스턴스가 유지돼야
  /// Scrollable.ensureVisible이 올바른 위치를 찾음).
  final Map<String, GlobalKey> _cardKeys = {};

  void _scrollToTicker(String ticker) {
    final ctx = _cardKeys[ticker]?.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 300), curve: Curves.easeOut, alignment: 0.05);
  }

  void _scrollToTop() {
    _scrollController.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  }

  @override
  void initState() {
    super.initState();
    _watches = _devices.listStockWatches();
    // 칩 눌러서 아래로 이동한 다음 다시 위로 돌아올 방법이 없다는 피드백으로
    // 스크롤 위로 버튼 추가 — 어느 정도 내려갔을 때만 보이게.
    _scrollController.addListener(() {
      final show = _scrollController.offset > 300;
      if (show != _showScrollTop) setState(() => _showScrollTop = show);
    });
    widget.api.getUsdKrwRate().then((rate) {
      if (mounted && rate != null) setState(() => _usdKrwRate = rate);
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _watches = _devices.listStockWatches();
    });
    await _watches;
  }

  Future<void> _removeTicker(int watchId) async {
    await _devices.deleteStockWatch(watchId);
    await _refresh();
  }

  Future<void> _showAddSheet() async {
    // 이미 추가한 티커는 미리보기/검색 결과에서 빼기 위해 넘겨줌 —
    // _watches는 이미 완료됐거나 진행 중인 Future라 다시 await해도
    // 새 네트워크 요청은 안 일어남.
    final currentTickers = (await _watches)?.map((w) => w.ticker).toSet() ?? <String>{};
    if (!mounted) return;
    final ticker = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      isScrollControlled: true,
      builder: (_) => _TickerSearchSheet(api: widget.api, currentTickers: currentTickers),
    );
    if (ticker == null) return;
    await _devices.addStockWatch(ticker);
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: _showScrollTop
          ? FloatingActionButton.small(
              onPressed: _scrollToTop,
              backgroundColor: AppColors.ink,
              tooltip: '맨 위로',
              child: const Icon(Icons.arrow_upward, color: Colors.white, size: 18),
            )
          : null,
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 56,
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: AppColors.ink),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const Expanded(
                    child: Text('관심 종목', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.ink)),
                  ),
                  TextButton.icon(
                    onPressed: _showAddSheet,
                    icon: const Icon(Icons.add, size: 16, color: AppColors.accent),
                    label: const Text(
                      '종목 추가',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.accent),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<List<StockWatch>>(
                future: _watches,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator(strokeWidth: 2));
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('불러오지 못했어요', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
                            const SizedBox(height: 6),
                            Text(
                              '${snapshot.error}',
                              style: TextStyle(fontSize: 12, color: AppColors.inkMuted),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton(onPressed: _refresh, child: const Text('다시 시도')),
                          ],
                        ),
                      ),
                    );
                  }

                  final watches = snapshot.data ?? [];
                  if (watches.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.show_chart, size: 28, color: AppColors.inkFaint),
                            const SizedBox(height: 10),
                            Text(
                              '아직 등록된 종목이 없어요',
                              style: TextStyle(color: AppColors.inkMuted, fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '위 "종목 추가"로 관심 있는 티커를 등록해보세요',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: AppColors.inkFaint, fontSize: 11.5, height: 1.4),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  // 섹터별로 묶되, 서버가 내려준 순서(첫 등장 순)를 그대로 섹터
                  // 순서로 씀 — 별도로 정렬하지 않음.
                  final bySector = <String, List<StockWatch>>{};
                  for (final w in watches) {
                    bySector.putIfAbsent(w.sector, () => []).add(w);
                    _cardKeys.putIfAbsent(w.ticker, () => GlobalKey());
                  }

                  return RefreshIndicator(
                    onRefresh: _refresh,
                    child: SingleChildScrollView(
                      // 티커 칩 클릭 → 스크롤 이동 기능 때문에 ListView 대신 이걸 씀.
                      // ListView는 children을 통째로 넘겨도 화면 밖으로 멀어진
                      // 항목은 내부적으로 언마운트함(가상화가 .builder 전용이
                      // 아니라 SliverList 계열 전체에 적용됨) — 그래서
                      // GlobalKey.currentContext가 null이 돼서 스크롤 이동이
                      // 조용히 실패했었음(2026-09-06 발견). 이 화면은 종목이
                      // 많아야 수십 개 수준이라 전부 마운트해둬도 성능에
                      // 문제없어서, 가상화 없는 이 위젯으로 바꿔서 해결함.
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final w in watches)
                                _TickerChip(
                                  label: w.ticker,
                                  quote: w.quote,
                                  onTap: () => _scrollToTicker(w.ticker),
                                  onRemove: () => _removeTicker(w.id),
                                ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          for (final entry in bySector.entries) ...[
                            _SectorLabel(entry.key),
                            const SizedBox(height: 6),
                            for (final w in entry.value) ...[
                              _StockCard(
                                key: _cardKeys[w.ticker],
                                watch: w,
                                showKrw: _showKrw,
                                usdKrwRate: _usdKrwRate,
                                onTapPrice: _toggleCurrency,
                              ),
                              const SizedBox(height: 8),
                            ],
                            const SizedBox(height: 8),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TickerChip extends StatelessWidget {
  const _TickerChip({required this.label, required this.onTap, required this.onRemove, this.quote});

  final String label;
  final StockQuote? quote;

  /// 라벨 부분을 누르면 그 종목 카드로 스크롤 이동(x 버튼과는 별도 영역).
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(2, 5, 6, 5),
      decoration: BoxDecoration(color: AppColors.accentSoft, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.accent)),
                  if (quote != null) ...[
                    const SizedBox(width: 4),
                    Text(
                      _formatPercent(quote!.percent),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: quote!.percent >= 0 ? AppColors.accent : AppColors.accent2,
                      ),
                    ),
                  ],
                  // 이 칩이 눌러서 이동 가능하다는 걸 보여주는 힌트 아이콘
                  // ("눌러도 되는지 잘 모르겠다"는 피드백으로 추가).
                  const SizedBox(width: 2),
                  Icon(Icons.arrow_downward, size: 10, color: AppColors.accent.withValues(alpha: 0.6)),
                ],
              ),
            ),
          ),
          InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: onRemove,
            child: const Icon(Icons.close, size: 14, color: AppColors.accent),
          ),
        ],
      ),
    );
  }
}

String _formatPercent(double percent) => '${percent >= 0 ? '+' : ''}${percent.toStringAsFixed(1)}%';

/// 소수점 둘째 자리까지의 달러 표시("$234.12").
String _formatUsd(double price) => '\$${price.toStringAsFixed(2)}';

/// 환율 곱해서 반올림 후 3자리마다 콤마 찍은 원화 표시("419,999원").
String _formatKrw(double usdPrice, double rate) {
  final won = (usdPrice * rate).round();
  final digits = won.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return '$buffer원';
}

/// 섹터별 색 — 카테고리 색과 겹치지 않게 별도로 둠(백엔드가 색을 안
/// 내려주고 섹터 이름 문자열만 주므로, 여기서 이름→색 매핑을 유지).
const Map<String, Color> _sectorColors = {
  '기술': Color(0xFF3D6FA8),
  '소비재': Color(0xFFA17A1F),
  '자동차': Color(0xFF4A8A4F),
  '금융': Color(0xFF5B6BB0),
  '헬스케어': Color(0xFFC04F7D),
  '에너지': Color(0xFFB3623A),
  '산업재': Color(0xFF7A7F6F),
  '통신': Color(0xFF3F8F8A),
  '소재': Color(0xFF8C6B4F),
  '부동산': Color(0xFF7A5BA0),
  '유틸리티': Color(0xFF4F7A6B),
};

Color _sectorColor(String sector) => _sectorColors[sector] ?? AppColors.inkFaint;

class _SectorLabel extends StatelessWidget {
  const _SectorLabel(this.sector);

  final String sector;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(
        children: [
          Container(width: 3, height: 12, decoration: BoxDecoration(color: _sectorColor(sector), borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 7),
          Text(
            sector,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.inkSoft, letterSpacing: 0.3),
          ),
        ],
      ),
    );
  }
}

class _StockCard extends StatelessWidget {
  const _StockCard({
    super.key,
    required this.watch,
    required this.showKrw,
    required this.usdKrwRate,
    required this.onTapPrice,
  });

  final StockWatch watch;

  /// 2026-09-07: 가격 탭하면 화면 전체가 달러/원화로 한 번에 바뀌는
  /// 토글 상태 — StockWatchScreen이 들고 있고 여기선 그대로 받아서
  /// 보여주기만 함(상태를 카드마다 따로 두면 "이 카드는 원인데 저
  /// 카드는 달러" 같은 혼란이 생겨서 화면 단위로 통일).
  final bool showKrw;
  final double? usdKrwRate;
  final VoidCallback onTapPrice;

  @override
  Widget build(BuildContext context) {
    final quote = watch.quote;
    return AppCard(
      radius: 12,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(color: AppColors.accent2Soft, borderRadius: BorderRadius.circular(5)),
                child: Text(watch.ticker, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.accent2)),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(watch.name, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.ink)),
              ),
              if (quote != null) ...[
                const SizedBox(width: 6),
                InkWell(
                  onTap: usdKrwRate == null ? null : onTapPrice,
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: showKrw && usdKrwRate != null
                              ? _formatKrw(quote.price, usdKrwRate!)
                              : _formatUsd(quote.price),
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink),
                        ),
                        TextSpan(
                          text: ' ${_formatPercent(quote.percent)}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: quote.percent >= 0 ? AppColors.accent : AppColors.accent2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (watch.news.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('아직 받아온 뉴스가 없어요', style: TextStyle(fontSize: 11.5, color: AppColors.inkFaint)),
            )
          else
            // 도트 대신 얇은 구분선으로 목록처럼 보이게 함(아이콘은 넣지
            // 말아달라던 예전 결정과 안 부딪히면서, 신문 지면에서 기사
            // 사이를 가르는 느낌 — expandable_issue_card.dart와 같은 처리).
            for (var i = 0; i < watch.news.length; i++) ...[
              if (i != 0) const Divider(height: 1, color: AppColors.divider),
              _NewsRow(item: watch.news[i]),
            ],
        ],
      ),
    );
  }
}

class _NewsRow extends StatelessWidget {
  const _NewsRow({required this.item});

  final StockNewsItem item;

  @override
  Widget build(BuildContext context) {
    final translated = item.titleKo;
    return InkWell(
      onTap: item.link.isEmpty ? null : () => launchUrl(Uri.parse(item.link), mode: LaunchMode.externalApplication),
      child: Padding(
        padding: const EdgeInsets.only(top: 7),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              translated ?? item.title,
              style: const TextStyle(fontSize: 11.5, color: AppColors.inkSoft, height: 1.4, decoration: TextDecoration.underline),
            ),
            // 번역 성공하면 원문(영어)을 옅은 글씨로 아래에 같이 보여줌 —
            // 번역 실패(키 없음/API 오류)하면 이 줄 없이 원문만 위에 나옴.
            if (translated != null) ...[
              const SizedBox(height: 2),
              Text(item.title, style: TextStyle(fontSize: 10, color: AppColors.inkFaint, height: 1.3)),
            ],
            const SizedBox(height: 1),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: item.source),
                  if (_formatPubDate(item.published) case final date?) TextSpan(text: ' · $date'),
                ],
              ),
              style: TextStyle(fontSize: 10, color: AppColors.inkFaint),
            ),
          ],
        ),
      ),
    );
  }
}

/// 야후 파이낸스 RSS의 pubDate(RFC 822, 예: "Sun, 06 Sep 2026 12:06:22
/// +0000")를 파싱해서 "오늘 기준인지 모르겠다"는 피드백에 맞게 보여줌 —
/// 오늘이면 시:분만, 아니면 날짜만(연도는 대개 올해라 생략). 웹에서도
/// 쓰는 화면이라 dart:io의 HttpDate 대신 직접 파싱함(RFC822 형식이
/// 고정적이라 간단한 파싱으로 충분).
String? _formatPubDate(String? raw) {
  if (raw == null) return null;
  final parts = raw.split(' ');
  if (parts.length < 5) return null;
  const months = {
    'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4, 'May': 5, 'Jun': 6,
    'Jul': 7, 'Aug': 8, 'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12,
  };
  final month = months[parts[2]];
  final day = int.tryParse(parts[1]);
  final year = int.tryParse(parts[3]);
  final timeParts = parts[4].split(':').map(int.tryParse).toList();
  if (month == null || day == null || year == null || timeParts.length != 3 || timeParts.contains(null)) {
    return null;
  }
  final utc = DateTime.utc(year, month, day, timeParts[0]!, timeParts[1]!, timeParts[2]!);
  final local = utc.toLocal();
  final now = DateTime.now();
  final isToday = local.year == now.year && local.month == now.month && local.day == now.day;
  if (isToday) {
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
  return '${local.month}월 ${local.day}일';
}

/// 종목 추가 바텀시트 — 2026-09-06: "티커를 미리 알고 있어야 하는 게
/// 불편하다"는 피드백으로, 티커를 직접 아는 사람만 위한 빈 입력창 대신
/// 회사 이름으로도 검색되는 자동완성을 추가함. 카탈로그(GET
/// /stocks/catalog)를 한 번만 받아서 타이핑마다 로컬에서 걸러냄(검색
/// 화면과 같은 패턴) — 그래도 목록에 없는 티커를 직접 입력해서
/// 추가하는 것도 여전히 가능함(직접 입력 후 완료 버튼).
class _TickerSearchSheet extends StatefulWidget {
  const _TickerSearchSheet({required this.api, required this.currentTickers});

  final ApiClient api;

  /// 이미 등록한 티커 — 미리보기/검색 결과에서 빼서 중복 추가를 막음.
  final Set<String> currentTickers;

  @override
  State<_TickerSearchSheet> createState() => _TickerSearchSheetState();
}

class _TickerSearchSheetState extends State<_TickerSearchSheet> {
  final _controller = TextEditingController();
  late final Future<List<StockCatalogEntry>> _catalog;
  String _query = '';

  /// 이미 추가한 티커를 또 추가하려고 하면 보여주는 안내 문구
  /// ("있는 건 추가 안 되어야 할 것 같다"는 피드백으로 추가).
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _catalog = widget.api.getStockCatalog();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit([String? ticker]) {
    final value = (ticker ?? _controller.text).trim().toUpperCase();
    if (value.isEmpty) return;
    if (widget.currentTickers.contains(value)) {
      setState(() => _errorText = '이미 추가된 종목이에요');
      return;
    }
    Navigator.of(context).pop(value);
  }

  /// 2026-09-06: "티커 순위별로 미리보기가 아래 있으면 좋겠다"는 피드백으로
  /// — 검색어가 없을 때도 카탈로그 앞부분(백엔드가 잘 알려진 순서로 정렬해
  /// 내려줌, stocks.py의 catalog() 참고)을 그대로 보여줌. 검색어가 있으면
  /// 기존처럼 티커/이름 매칭으로 걸러냄. 둘 다 이미 등록한 티커는 뺌.
  List<StockCatalogEntry> _visible(List<StockCatalogEntry> all) {
    final pool = all.where((e) => !widget.currentTickers.contains(e.ticker));
    final q = _query.trim().toUpperCase();
    if (q.isEmpty) return pool.take(8).toList();
    return pool.where((e) => e.ticker.contains(q) || e.name.toUpperCase().contains(q)).take(8).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('종목 추가', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.ink)),
          const SizedBox(height: 4),
          Text('회사 이름이나 티커로 검색하세요 (예: 애플, AAPL)', style: TextStyle(fontSize: 12, color: AppColors.inkFaint)),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                  onChanged: (v) => setState(() {
                    _query = v;
                    _errorText = null;
                  }),
                  onSubmitted: (_) => _submit(),
                  style: const TextStyle(fontSize: 14, color: AppColors.ink),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'AAPL 또는 애플',
                    hintStyle: TextStyle(fontSize: 14, color: AppColors.inkFaint),
                    filled: true,
                    fillColor: AppColors.chipBg,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(onPressed: () => _submit(), icon: const Icon(Icons.add_circle, color: AppColors.accent)),
            ],
          ),
          if (_errorText != null) ...[
            const SizedBox(height: 6),
            Text(_errorText!, style: TextStyle(fontSize: 12, color: AppColors.accent2)),
          ],
          FutureBuilder<List<StockCatalogEntry>>(
            future: _catalog,
            builder: (context, snapshot) {
              final matches = _visible(snapshot.data ?? const []);
              if (matches.isEmpty) {
                // 카탈로그에 없는 티커를 입력 중일 때 — "추가가 안 된다"고
                // 오해하지 않게, + 버튼으로 직접 추가할 수 있다는 걸 알려줌
                // ("Spce 추가하려니 안 되네" 피드백으로 추가).
                if (_query.trim().isNotEmpty && _errorText == null) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '목록에 없는 티커예요 — 오른쪽 + 버튼으로 직접 추가할 수 있어요',
                      style: TextStyle(fontSize: 11.5, color: AppColors.inkFaint),
                    ),
                  );
                }
                return const SizedBox.shrink();
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 12),
                  Text(
                    _query.trim().isEmpty ? '인기 종목' : '검색 결과',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.inkFaint, letterSpacing: 0.3),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 240),
                    decoration: BoxDecoration(
                      color: AppColors.chipBg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: matches.length,
                      separatorBuilder: (_, _) => const Divider(height: 1, color: AppColors.divider),
                      itemBuilder: (context, i) {
                        final m = matches[i];
                        return InkWell(
                          onTap: () => _submit(m.ticker),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                      color: AppColors.accent2Soft, borderRadius: BorderRadius.circular(5)),
                                  child: Text(
                                    m.ticker,
                                    style: const TextStyle(
                                        fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.accent2),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(m.name, style: const TextStyle(fontSize: 13, color: AppColors.ink)),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
