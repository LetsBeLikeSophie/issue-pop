import 'package:flutter/material.dart';

import '../favorites_store.dart';
import '../theme.dart';
import '../widgets/expandable_issue_card.dart';

class ArchiveScreen extends StatefulWidget {
  const ArchiveScreen({super.key});

  @override
  State<ArchiveScreen> createState() => _ArchiveScreenState();
}

class _ArchiveScreenState extends State<ArchiveScreen> {
  final _favorites = FavoritesStore();
  late Future<List<SavedIssue>> _saved;

  @override
  void initState() {
    super.initState();
    _saved = _favorites.getAll();
  }

  void _reload() => setState(() => _saved = _favorites.getAll());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                  const Text(
                    '저장한 이슈',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.ink),
                  ),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<List<SavedIssue>>(
                future: _saved,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final items = snapshot.data ?? [];
                  if (items.isEmpty) {
                    return Center(
                      child: Text(
                        '아직 저장한 이슈가 없어요',
                        style: TextStyle(color: AppColors.inkMuted, fontSize: 13),
                      ),
                    );
                  }
                  final maxOutlet =
                      items.map((i) => i.issue.outletCount).reduce((a, b) => a > b ? a : b);
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(16, 2, 16, 24),
                    children: [
                      for (var i = 0; i < items.length; i++) ...[
                        ExpandableIssueCard(
                          key: ValueKey(items[i].issue.id),
                          issue: items[i].issue,
                          maxOutletCount: maxOutlet,
                          subtitle: '저장일 ${items[i].savedAt.month}월 ${items[i].savedAt.day}일',
                          onFavoriteChanged: _reload,
                        ),
                        if (i != items.length - 1) const SizedBox(height: 8),
                      ],
                    ],
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
