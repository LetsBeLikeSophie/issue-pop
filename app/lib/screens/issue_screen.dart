import 'package:flutter/material.dart';

import '../api_client.dart';
import '../models/issue.dart';
import '../theme.dart';
import '../theme_store.dart';
import '../widgets/error_retry.dart';
import '../widgets/expandable_issue_card.dart';
import '../widgets/screen_header.dart';

/// 2026-10-13: 푸시 알림(다이제스트/관심 키워드)을 눌렀을 때 그 이슈를 바로
/// 펼쳐서 보여주는 화면(push_router.dart가 띄움).
///
/// 이슈 id는 재클러스터링 때마다 바뀔 수 있어서(서버 _make_id) 알림을 한참 뒤에
/// 누르면 그 id가 이미 없을 수 있음 — 그땐 알림에 같이 실려온 대표 키워드로
/// 지금 목록에서 가장 기사 많은 이슈를 대신 찾아 보여주고, 그것도 없으면
/// "더 이상 목록에 없다"고 안내함.
class IssueScreen extends StatefulWidget {
  const IssueScreen({super.key, required this.api, required this.issueId, this.keyword});

  final ApiClient api;
  final String issueId;
  final String? keyword;

  @override
  State<IssueScreen> createState() => _IssueScreenState();
}

class _IssueScreenState extends State<IssueScreen> {
  late Future<IssueDetail?> _issue = _load();

  Future<IssueDetail?> _load() async {
    try {
      return await widget.api.getIssue(widget.issueId);
    } on ApiException catch (e) {
      if (e.statusCode != 404) rethrow;
    }
    final keyword = widget.keyword;
    if (keyword == null || keyword.isEmpty) return null;
    final index = await widget.api.getIndex();
    final matches = index
        .where((i) => i.keyword == keyword || i.keywords.contains(keyword))
        .toList()
      ..sort((a, b) => b.articleCount.compareTo(a.articleCount));
    if (matches.isEmpty) return null;
    return widget.api.getIssue(matches.first.id);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeStore.instance,
      builder: (context, _) => Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              const ScreenHeader(title: '알림으로 온 이슈'),
              Expanded(
                child: FutureBuilder<IssueDetail?>(
                  future: _issue,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
                    }
                    if (snapshot.hasError) {
                      return ErrorRetry(
                        error: '${snapshot.error}',
                        onRetry: () => setState(() => _issue = _load()),
                      );
                    }
                    final issue = snapshot.data;
                    if (issue == null) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Text(
                            '이 이슈는 지금 목록에 더 이상 없어요.\n홈에서 최신 이슈를 확인해보세요.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 13, color: AppColors.inkSoft, height: 1.5),
                          ),
                        ),
                      );
                    }
                    return ListView(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      children: [
                        ExpandableIssueCard(
                          issue: issue,
                          api: widget.api,
                          maxOutletCount: issue.outletCount,
                          initiallyExpanded: true,
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
