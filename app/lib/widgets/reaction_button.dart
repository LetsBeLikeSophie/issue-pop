import 'package:flutter/material.dart';

import '../models/reaction.dart';
import '../reaction_store.dart';
import '../theme.dart';

/// 2026-10-13: 이슈 카드 우측 하단(카테고리 배지 아래, 사이는 여백)에 붙는 반응 버튼.
/// 접힌 카드에는 가장 많이 눌린 반응 하나(아이콘 + 수)만 작게 보이고(아직 반응이
/// 없으면 반응 추가 아이콘만), 누르면 고정 반응 5개가 떠올라서 하나를 고름. 한
/// 카드에 하나만 — 다른 걸 고르면 바뀌고, 이미 고른 걸 다시 누르면 취소됨. 내가 고른
/// 게 있으면 버튼이 강조색.
///
/// 2026-10-14: 눈에 보이는 크기는 작게 두되 눌리는 영역은 최소 40x30으로 키움. 카드가
/// 너무 커지지 않도록 높이는 이 정도로만.
class ReactionButton extends StatelessWidget {
  const ReactionButton({super.key, required this.keyword});

  final String keyword;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ReactionSummary?>(
      valueListenable: ReactionStore.instance.watch(keyword),
      builder: (context, summary, _) {
        final s = summary ?? ReactionSummary.empty;
        final top = reactionKindOf(s.top);
        final color = s.mine != null ? AppColors.accent : AppColors.inkSoft;
        return Builder(
          builder: (buttonContext) => Semantics(
            button: true,
            label: '반응 고르기',
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => _openPopup(buttonContext, keyword, s),
              child: Container(
                constraints: const BoxConstraints(minWidth: 40, minHeight: 30),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                alignment: Alignment.center,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(top?.icon ?? Icons.add_reaction_outlined, size: 17, color: color),
                    if (top != null) ...[
                      const SizedBox(width: 3),
                      Text(
                        '${s.counts[top.key]}',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

Future<void> _openPopup(BuildContext buttonContext, String keyword, ReactionSummary summary) async {
  final box = buttonContext.findRenderObject() as RenderBox;
  final overlay = Overlay.of(buttonContext).context.findRenderObject() as RenderBox;
  final rect = Rect.fromPoints(
    box.localToGlobal(Offset.zero, ancestor: overlay),
    box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
  );
  final picked = await showMenu<String>(
    context: buttonContext,
    position: RelativeRect.fromRect(rect, Offset.zero & overlay.size),
    // 앱의 다른 카드(AppCard)와 같은 톤: 흰 배경 + 옅은 라인 테두리 + 반지름 10. 그림자는 카드
    // 위에 떠 있는 걸 구분할 정도로만 아주 약하게(예전엔 고도 6 + 머티리얼3 틴트로 너무 강했음).
    color: AppColors.surface,
    elevation: 2,
    shadowColor: Colors.black.withValues(alpha: 0.18),
    surfaceTintColor: Colors.transparent,
    menuPadding: EdgeInsets.zero,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
      side: BorderSide(color: AppColors.line),
    ),
    constraints: const BoxConstraints(minWidth: 0, maxWidth: 320),
    items: [_ReactionMenuEntry(summary: summary)],
  );
  if (picked == null || !buttonContext.mounted) return;
  final result = await ReactionStore.instance.choose(keyword, picked);
  if (!buttonContext.mounted) return;
  final message = switch (result) {
    ReactionSetResult.ok => null,
    ReactionSetResult.issueGone => '지금 목록에 없는 이슈예요',
    ReactionSetResult.failed => '반응을 남기지 못했어요. 잠시 후 다시 시도해주세요',
  };
  if (message == null) return;
  ScaffoldMessenger.of(buttonContext)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), duration: const Duration(milliseconds: 1800), behavior: SnackBarBehavior.floating));
}

/// 떠오르는 팝업 안쪽 — "이 소식에 대한 내 반응" 아래에 5개를 한 줄로.
class _ReactionMenuEntry extends PopupMenuEntry<String> {
  const _ReactionMenuEntry({required this.summary});

  final ReactionSummary summary;

  @override
  double get height => 104;

  @override
  bool represents(String? value) => false;

  @override
  State<_ReactionMenuEntry> createState() => _ReactionMenuEntryState();
}

class _ReactionMenuEntryState extends State<_ReactionMenuEntry> {
  @override
  Widget build(BuildContext context) {
    final s = widget.summary;
    return SizedBox(
      width: 304,
      child: Padding(
        // 카드 안쪽 여백(12~14)과 맞춤.
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 2, bottom: 8),
              child: Text('이 소식에 대한 내 반응', style: TextStyle(fontSize: 11, color: AppColors.inkFaint)),
            ),
            Row(
              children: [
                for (final kind in kReactionKinds)
                  Expanded(
                    child: _Option(
                      kind: kind,
                      count: s.counts[kind.key] ?? 0,
                      selected: s.mine == kind.key,
                      onTap: () => Navigator.of(context).pop(kind.key),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({required this.kind, required this.count, required this.selected, required this.onTap});

  final ReactionKind kind;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.accent : AppColors.inkSoft;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.accentSoft : null,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(kind.icon, size: 24, color: color),
            const SizedBox(height: 2),
            Text(
              kind.label,
              maxLines: 1,
              style: TextStyle(fontSize: 10.5, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: color),
            ),
            Text(
              count > 0 ? '$count' : ' ',
              style: TextStyle(fontSize: 10, color: AppColors.inkFaint),
            ),
          ],
        ),
      ),
    );
  }
}
