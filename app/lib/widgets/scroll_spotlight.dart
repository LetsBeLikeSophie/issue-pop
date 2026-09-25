import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../theme.dart';

/// 2026-09-25: keyword_watch_screen/stock_watch_screen 두 화면이 "칩을
/// 누르면 그 카드로 스크롤 이동" + "어느 정도 내려가면 맨 위로 버튼
/// 등장" 로직을 ScrollController/GlobalKey map/리스너까지 통째로 복붙해
/// 갖고 있어서 하나로 뺌 — 같은 로직이 두 곳에 있으면 버그 고칠 때
/// 한쪽만 고치고 잊어버리기 쉬움.
///
/// 2026-09-26: "위로"뿐 아니라 "아래로" 버튼도 같이 달라는 요청으로
/// showScrollBottom/scrollToBottom을 추가하고, 홈 화면에도 적용함.
///
/// 사용법: State에서 `late final _spotlight = ScrollSpotlightController();`
/// 로 들고, `_spotlight.scrollController`를 스크롤 위젯에 연결하고,
/// 항목마다 `key: _spotlight.keyFor(id)`를 달아주면 됨. dispose()에서
/// `_spotlight.dispose()` 호출 필수.
class ScrollSpotlightController extends ChangeNotifier {
  ScrollSpotlightController() {
    scrollController.addListener(_onScroll);
    // 스크롤을 한 번도 안 해도(=콘텐츠가 처음부터 화면보다 길면) "아래로"
    // 버튼이 바로 보여야 해서, 첫 프레임이 그려진 직후(스크롤 metrics가
    // 확정된 시점) 한 번 더 계산함 — 리스너는 실제로 스크롤해야만 불림.
    SchedulerBinding.instance.addPostFrameCallback((_) => _onScroll());
  }

  final scrollController = ScrollController();
  final Map<String, GlobalKey> _keys = {};
  bool showScrollTop = false;
  bool showScrollBottom = false;

  void _onScroll() {
    if (!scrollController.hasClients) return;
    final position = scrollController.position;
    final top = position.pixels > 300;
    final bottom = position.maxScrollExtent - position.pixels > 300;
    if (top != showScrollTop || bottom != showScrollBottom) {
      showScrollTop = top;
      showScrollBottom = bottom;
      notifyListeners();
    }
  }

  /// 항목별 GlobalKey — 같은 id로 다시 부르면 기존 키를 그대로 돌려줌
  /// (build()마다 새로 만들면 Scrollable.ensureVisible이 위치를 못
  /// 찾음, 2026-09-06에 발견됐던 것과 같은 문제).
  GlobalKey keyFor(String id) => _keys.putIfAbsent(id, () => GlobalKey());

  void scrollTo(String id) {
    final ctx = _keys[id]?.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 300), curve: Curves.easeOut, alignment: 0.05);
  }

  void scrollToTop() {
    scrollController.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  }

  void scrollToBottom() {
    scrollController.animateTo(
      scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    scrollController.dispose();
    super.dispose();
  }
}

/// [ScrollSpotlightController]의 위치에 따라 "맨 위로"/"맨 아래로"
/// 버튼을 필요한 것만 세로로 쌓아서 보여줌. 둘 다 숨겨져 있으면 크기
/// 0이라 탭 영역도 없음.
class ScrollJumpFab extends StatelessWidget {
  const ScrollJumpFab({super.key, required this.controller});

  final ScrollSpotlightController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (!controller.showScrollTop && !controller.showScrollBottom) return const SizedBox.shrink();
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (controller.showScrollTop) ...[
              _JumpButton(icon: Icons.arrow_upward, tooltip: '맨 위로', onPressed: controller.scrollToTop),
              if (controller.showScrollBottom) const SizedBox(height: 8),
            ],
            if (controller.showScrollBottom)
              _JumpButton(icon: Icons.arrow_downward, tooltip: '맨 아래로', onPressed: controller.scrollToBottom),
          ],
        );
      },
    );
  }
}

class _JumpButton extends StatelessWidget {
  const _JumpButton({required this.icon, required this.tooltip, required this.onPressed});

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.small(
      onPressed: onPressed,
      backgroundColor: AppColors.ink,
      tooltip: tooltip,
      child: Icon(icon, color: Colors.white, size: 18),
    );
  }
}
