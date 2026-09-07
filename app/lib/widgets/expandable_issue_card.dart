import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api_client.dart';
import '../favorites_store.dart';
import '../models/issue.dart';
import '../theme.dart';

/// 이슈 하나를 나타내는 카드 — "이슈판" 프로토타입 아티팩트의 카드
/// 레이아웃을 그대로 앱에 옮긴 것(랭크·카테고리 배지·세리프 키워드·
/// 매체 도달 도트·기사수·펼치면 매체별로 묶인 기사 링크).
///
/// 2026-08-24: [issue]가 이미 IssueDetail(기사 목록 포함, 홈 기본
/// 목록처럼 /trending에서 통째로 받아온 경우)이면 펼치기가 네트워크 없이
/// 즉시 반응함. 반대로 [issue]가 요약(IssueSummary, 검색 결과처럼 가볍게
/// 받아온 경우)이면 펼칠 때 그제서야 [api]로 상세를 받아옴 — 검색 결과
/// 전체에 기사 목록까지 미리 실었더니 타이핑마다 무거워진다는 피드백을
/// 받고 이렇게 나눔.
///
/// 2026-08-28: 즐겨찾기 저장/해제를 북마크 아이콘 탭 대신 좌우 스와이프로
/// 바꿈("메시지 지우듯이" 스와이프하는 게 낫겠다는 피드백) — 홈/검색에서는
/// 스와이프하면 "저장"/"저장 취소" 액션이, 저장한 이슈 화면([archiveMode])
/// 에서는 "삭제" 액션이 나옴. 즐겨찾기 상태는 이제 FavoritesStore
/// (ChangeNotifier 싱글턴)를 구독해서 표시하므로, 어느 화면에서 바꾸든
/// 다른 화면의 카드도 항상 최신 상태로 보임(예전엔 콜백을 못 받은 화면의
/// 카드가 낡은 상태로 남는 버그가 있었음).
class ExpandableIssueCard extends StatefulWidget {
  const ExpandableIssueCard({
    super.key,
    required this.issue,
    this.api,
    this.rank,
    this.maxOutletCount = 1,
    this.subtitle,
    this.archiveMode = false,
  });

  final IssueSummary issue;

  /// [issue]가 IssueDetail이 아닐 때(=검색 결과 등 요약만 있을 때)
  /// 펼칠 때 상세를 받아오는 데 씀. IssueDetail을 이미 들고 있는
  /// 카드(홈 기본 목록 등)에서는 필요 없음.
  final ApiClient? api;
  final int? rank;

  /// 매체 도달 도트를 몇 칸까지 그릴지 — 현재 목록 전체에서 가장 많이
  /// 보도된 이슈의 outlet_count(이슈판의 N_OUTLETS와 동일한 개념).
  final int maxOutletCount;

  /// 카테고리 배지 아래 보여줄 캡션 (예: 아카이브의 "저장일 8월 24일").
  final String? subtitle;

  /// 저장한 이슈 화면에서 쓰면 true — 스와이프 액션이 "저장"이 아니라
  /// "삭제"로 바뀜(이 화면의 카드는 항상 이미 저장된 상태라서).
  final bool archiveMode;

  @override
  State<ExpandableIssueCard> createState() => _ExpandableIssueCardState();
}

class _ExpandableIssueCardState extends State<ExpandableIssueCard> {
  bool _expanded = false;
  Future<IssueDetail>? _detail;

  @override
  void initState() {
    super.initState();
    if (widget.issue case final IssueDetail d) {
      _detail = Future.value(d);
    }
  }

  void _toggleExpand() {
    setState(() {
      _expanded = !_expanded;
      _detail ??= widget.api!.getIssue(widget.issue.id);
    });
  }

  Future<void> _toggleSave() async {
    // 즐겨찾기는 기사 목록까지 저장해두는 구조라(favorites_store.dart),
    // 요약만 있는 카드(검색 결과)에서 저장하려면 먼저 상세를 받아야 함.
    final full = await (_detail ??= widget.api!.getIssue(widget.issue.id));
    final nowSaved = await FavoritesStore.instance.toggle(full);
    if (!mounted) return;
    // 스와이프만으로는 저장/삭제가 됐는지 눈에 안 띈다는 피드백을 받고
    // 추가함 — 잠깐 나타났다 사라지는 스낵바로 결과를 확인해줌.
    final message = widget.archiveMode ? '삭제했어요' : (nowSaved ? '저장했어요' : '저장을 취소했어요');
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        // SnackBar는 content를 내부적으로 Expanded로 감싸서, 고정 width를
        // 주면 짧은 문장이 왼쪽 정렬된 채 오른쪽에 빈 공간이 남는
        // 버그처럼 보이는 현상이 있었음 — Center로 감싸서 해결.
        content: Center(child: Text(message)),
        duration: const Duration(milliseconds: 1400),
        behavior: SnackBarBehavior.floating,
        width: 180,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final issue = widget.issue;
    final catColor = CategoryColors.of(issue.category);
    final keywords = issue.keywords.isEmpty ? [issue.keyword] : issue.keywords;
    final isSingle = issue.outletCount <= 1;

    return ListenableBuilder(
      listenable: FavoritesStore.instance,
      builder: (context, _) {
        final saved = FavoritesStore.instance.isSaved(issue.id);

        return Slidable(
          key: ValueKey('slidable-${issue.id}'),
          endActionPane: ActionPane(
            motion: const DrawerMotion(),
            extentRatio: 0.26,
            // 저장한 이슈 화면([archiveMode])의 삭제는 실제로 카드가 목록에서
            // 빠지는 동작이라 onDismissed로 진짜 사라지게 함. 홈/검색의
            // 저장은 반대로 카드가 계속 그 자리에 남아있어야 해서(즐겨찾기
            // 여부만 토글) confirmDismiss 안에서 토글만 하고 항상 false를
            // 반환 — closeOnCancel로 원래 자리로 스르륵 돌아가게 함. 끝까지
            // 밀면 버튼을 안 눌러도 바로 저장/취소되고, 다시 끝까지 밀면
            // 반대로 토글됨.
            dismissible: widget.archiveMode
                ? DismissiblePane(onDismissed: _toggleSave)
                : DismissiblePane(
                    // confirmDismiss가 항상 false를 반환해서 실제로는
                    // 절대 호출 안 되지만, 생성자가 필수로 요구함.
                    onDismissed: () {},
                    confirmDismiss: () async {
                      await _toggleSave();
                      return false;
                    },
                    closeOnCancel: true,
                  ),
            children: [
              if (widget.archiveMode)
                SlidableAction(
                  onPressed: (_) => _toggleSave(),
                  backgroundColor: AppColors.accent2,
                  foregroundColor: Colors.white,
                  icon: Icons.delete_outline,
                  label: '삭제',
                )
              else
                SlidableAction(
                  onPressed: (context) {
                    _toggleSave();
                    Slidable.of(context)?.close();
                  },
                  // "저장 취소"는 버튼 폭에서 잘려서 "취소"로 줄임. 아이콘만으로는
                  // 저장/취소 구분이 잘 안 보인다는 피드백으로 배경색도 상태에
                  // 따라 다르게 함(삭제와 같은 accent2 톤 재사용).
                  backgroundColor: saved ? AppColors.accent2 : AppColors.accent,
                  foregroundColor: Colors.white,
                  icon: saved ? Icons.bookmark_remove_outlined : Icons.bookmark_add_outlined,
                  label: saved ? '취소' : '저장',
                ),
            ],
          ),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: AppColors.line),
              borderRadius: BorderRadius.circular(10),
              boxShadow: AppColors.cardShadow,
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: _toggleExpand,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        if (widget.rank != null) ...[
                          SizedBox(
                            width: 20,
                            child: Text(
                              '${widget.rank}',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: AppColors.inkFaint,
                                fontFeatures: const [FontFeature.tabularFigures()],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 7,
                                runSpacing: 2,
                                children: [
                                  Text(
                                    keywords.first,
                                    style: AppTypography.serif(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.ink,
                                    ),
                                  ),
                                  if (keywords.length > 1)
                                    Text.rich(
                                      TextSpan(children: [
                                        TextSpan(
                                          text: '· ',
                                          style: TextStyle(color: AppColors.inkFaint),
                                        ),
                                        TextSpan(
                                          text: keywords[1],
                                          style: AppTypography.serif(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.inkSoft,
                                          ),
                                        ),
                                      ]),
                                    ),
                                  _CategoryBadge(category: issue.category, color: catColor),
                                  if (isSingle) const _SingleTag(),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                issue.representativeTitle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12, color: AppColors.inkSoft, height: 1.35),
                              ),
                              if (widget.subtitle != null) ...[
                                const SizedBox(height: 3),
                                Text(widget.subtitle!, style: TextStyle(fontSize: 11, color: AppColors.inkFaint)),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        _ReachDots(count: issue.outletCount, max: widget.maxOutletCount),
                        const SizedBox(width: 12),
                        _CountStat(count: issue.articleCount),
                        const SizedBox(width: 6),
                        AnimatedRotation(
                          turns: _expanded ? 0.25 : 0,
                          duration: const Duration(milliseconds: 150),
                          child: Icon(Icons.chevron_right, size: 16, color: AppColors.inkFaint),
                        ),
                      ],
                    ),
                  ),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOut,
                  child: _expanded ? _ExpandedBody(detail: _detail!) : const SizedBox(width: double.infinity),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CategoryBadge extends StatelessWidget {
  const _CategoryBadge({required this.category, required this.color});

  final String category;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
      child: Text(
        category,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color, letterSpacing: 0.02),
      ),
    );
  }
}

class _SingleTag extends StatelessWidget {
  const _SingleTag();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(color: AppColors.accent2Soft, borderRadius: BorderRadius.circular(4)),
      child: const Text(
        '단독',
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.accent2, letterSpacing: 0.02),
      ),
    );
  }
}

/// "이슈판"의 .dots — 오늘 가장 많이 보도된 이슈(maxOutletCount)를
/// 기준으로 칸을 만들고, 이 이슈가 보도된 매체 수만큼 채움.
class _ReachDots extends StatelessWidget {
  const _ReachDots({required this.count, required this.max});

  final int count;
  final int max;

  @override
  Widget build(BuildContext context) {
    final total = max < 1 ? 1 : max;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: 2.5,
          runSpacing: 2.5,
          alignment: WrapAlignment.end,
          children: [
            for (var i = 0; i < total; i++)
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i < count ? AppColors.accent : AppColors.line,
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text('$count개 매체', style: TextStyle(fontSize: 10, color: AppColors.inkFaint)),
      ],
    );
  }
}

class _CountStat extends StatelessWidget {
  const _CountStat({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$count',
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppColors.ink,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        Text('건', style: TextStyle(fontSize: 10, color: AppColors.inkFaint)),
      ],
    );
  }
}

class _ExpandedBody extends StatelessWidget {
  const _ExpandedBody({required this.detail});

  final Future<IssueDetail> detail;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
      child: FutureBuilder<IssueDetail>(
        future: detail,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
            );
          }
          if (snapshot.hasError) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text('불러오지 못했어요', style: TextStyle(fontSize: 12.5, color: AppColors.inkFaint)),
            );
          }
          final articles = snapshot.data!.articles;
          if (articles.isEmpty) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text('관련 기사가 없어요', style: TextStyle(fontSize: 12.5, color: AppColors.inkFaint)),
            );
          }
          final grouped = <String, List<ArticleOut>>{};
          for (final a in articles) {
            grouped.putIfAbsent(a.outlet, () => []).add(a);
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final entry in grouped.entries) _OutletGroup(outlet: entry.key, articles: entry.value),
            ],
          );
        },
      ),
    );
  }
}

class _OutletGroup extends StatelessWidget {
  const _OutletGroup({required this.outlet, required this.articles});

  final String outlet;
  final List<ArticleOut> articles;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: AppColors.accentSoft, borderRadius: BorderRadius.circular(4)),
            child: Text(
              '$outlet ${articles.length}건',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.accent),
            ),
          ),
          const SizedBox(height: 6),
          // 2026-09-06: 기사가 여러 건일 때 "목록처럼" 안 읽힌다는 피드백으로
          // 도트 대신 얇은 구분선을 넣음 — 아이콘은 넣지 말아달라던 예전
          // 결정과는 안 부딪히고(구분선은 아이콘이 아니라 지면 요소), 도트보다
          // 신문 지면에서 기사 사이를 가르는 느낌이라 이 앱 톤에 더 맞음.
          for (var i = 0; i < articles.length; i++) ...[
            if (i != 0) const Divider(height: 1, color: AppColors.divider),
            _ArticleLine(article: articles[i]),
          ],
        ],
      ),
    );
  }
}

/// 기사 한 줄 — 밑줄(언더라인)로 "이건 눌러서 원문으로 나가는 링크"라는
/// 걸 표시함. 아이콘은 넣지 말아달라는 피드백이 있어서 밑줄 하나로만
/// 처리했음.
///
/// 2026-09-07: "기사에 사진 없으니 심심하다"는 피드백으로 썸네일 추가 —
/// 매체마다 이미지가 있는 곳/없는 곳이 섞여 있어서(fetcher.py의
/// _extract_image), 있는 기사만 왼쪽에 작은 정사각형으로 보여주고 없는
/// 기사는 지금처럼 텍스트만(시안 A안, 아티팩트로 먼저 비교해보고 확정함).
class _ArticleLine extends StatelessWidget {
  const _ArticleLine({required this.article});

  final ArticleOut article;

  @override
  Widget build(BuildContext context) {
    final image = article.image;
    return InkWell(
      onTap: article.link.isEmpty
          ? null
          : () => launchUrl(Uri.parse(article.link), mode: LaunchMode.externalApplication),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (image != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.network(
                  // 2026-09-07: 매체 이미지 서버가 CORS 허용 헤더를 안 보내서
                  // Flutter 웹(CanvasKit)이 직접 못 그림(실측 확인 — 브라우저
                  // <img> 태그로는 잘 뜨는데 캔버스 텍스처로 올릴 때만 막힘).
                  // 서버 프록시(GET /image-proxy)를 거쳐서 받아옴.
                  ApiClient.proxyImageUrl(image),
                  width: 44,
                  height: 44,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(width: 44, height: 44, color: AppColors.surfaceAlt),
                  loadingBuilder: (context, child, progress) =>
                      progress == null ? child : Container(width: 44, height: 44, color: AppColors.surfaceAlt),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                article.title,
                style: TextStyle(
                  fontSize: 12.5,
                  color: AppColors.accent,
                  height: 1.5,
                  decoration: TextDecoration.underline,
                  decorationColor: AppColors.accent.withValues(alpha: 0.35),
                  decorationThickness: 1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
