import 'package:flutter/material.dart';

import '../theme.dart';

/// 2026-09-25: keyword_watch_screen/stock_watch_screen 두 화면이 "칩을
/// 누르면 그 카드로 스크롤 이동" + "어느 정도 내려가면 맨 위로 버튼
/// 등장" 로직을 ScrollController/GlobalKey map/리스너까지 통째로 복붙해
/// 갖고 있어서 하나로 뺌 — 같은 로직이 두 곳에 있으면 버그 고칠 때
/// 한쪽만 고치고 잊어버리기 쉬움.
///
/// 사용법: State에서 `late final _spotlight = ScrollSpotlightController();`
/// 로 들고, `_spotlight.scrollController`를 스크롤 위젯에 연결하고,
/// 항목마다 `key: _spotlight.keyFor(id)`를 달아주면 됨. dispose()에서
/// `_spotlight.dispose()` 호출 필수.
class ScrollSpotlightController extends ChangeNotifier {
  ScrollSpotlightController() {
    scrollController.addListener(_onScroll);
  }

  final scrollController = ScrollController();
  final Map<String, GlobalKey> _keys = {};
  bool showScrollTop = false;

  void _onScroll() {
    final show = scrollController.offset > 300;
    if (show != showScrollTop) {
      showScrollTop = show;
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

  @override
  void dispose() {
    scrollController.dispose();
    super.dispose();
  }
}

/// [ScrollSpotlightController.showScrollTop]에 따라 나타났다 사라지는
/// "맨 위로" FAB. 숨겨져 있을 때는 크기 0이라 탭 영역도 없음.
class ScrollTopFab extends StatelessWidget {
  const ScrollTopFab({super.key, required this.controller});

  final ScrollSpotlightController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (!controller.showScrollTop) return const SizedBox.shrink();
        return FloatingActionButton.small(
          onPressed: controller.scrollToTop,
          backgroundColor: AppColors.ink,
          tooltip: '맨 위로',
          child: const Icon(Icons.arrow_upward, color: Colors.white, size: 18),
        );
      },
    );
  }
}
