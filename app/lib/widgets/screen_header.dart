import 'package:flutter/material.dart';

import '../theme.dart';

/// 2026-09-25: archive_screen/keyword_watch_screen/settings_screen/
/// stock_watch_screen 네 화면이 "뒤로가기 + 제목(+선택적 우측 액션)"을
/// 각자 따로 그리고 있어서 하나로 뺌. 우측 액션은 지금까지 전부
/// "+ 아이콘 + 텍스트" 모양(TextButton.icon)이었던 패턴만 지원함 —
/// 다른 모양이 필요해지면 그때 trailing을 임의 Widget으로 바꾸면 됨.
class ScreenHeader extends StatelessWidget {
  const ScreenHeader({super.key, required this.title, this.trailingLabel, this.onTrailingTap});

  final String title;
  final String? trailingLabel;
  final VoidCallback? onTrailingTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back_ios_new, size: 18, color: AppColors.ink),
            onPressed: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: Text(title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.ink)),
          ),
          if (trailingLabel != null) ...[
            TextButton.icon(
              onPressed: onTrailingTap,
              icon: Icon(Icons.add, size: 16, color: AppColors.accent),
              label: Text(
                trailingLabel!,
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.accent),
              ),
            ),
            const SizedBox(width: 4),
          ],
        ],
      ),
    );
  }
}
