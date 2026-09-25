import 'package:flutter/material.dart';

import '../theme.dart';

/// 2026-09-25: 관심 종목의 티커 칩(_TickerChip)과 관심 워치의 키워드 칩
/// (_KeywordChip), 설정 화면의 관심 키워드 칩(또 다른 _KeywordChip —
/// 이름이 같은 별개 위젯이 두 파일에 있었음)까지 세 군데가 "라벨 +
/// (선택) 부가 텍스트 + X 버튼"의 알약 모양을 각자 그리고 있어서
/// 하나로 뺌. [onTap]이 있으면 라벨 영역이 눌러서 이동 가능한 버튼이
/// 되고(관심 종목/워치의 스크롤 이동용), 없으면 라벨이 그냥 고정
/// 텍스트로만 나옴(설정 화면의 키워드 목록처럼).
class RemovableChip extends StatelessWidget {
  const RemovableChip({
    super.key,
    required this.label,
    this.trailing,
    this.onTap,
    required this.onRemove,
  });

  final String label;

  /// 라벨 옆에 덧붙일 위젯(예: 등락률 텍스트). 없으면 라벨만 표시.
  final Widget? trailing;

  /// 있으면 라벨 영역이 눌러서 이동 가능한 버튼이 됨. 없으면 라벨은
  /// 그냥 고정 텍스트.
  final VoidCallback? onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final labelRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.accent)),
        if (trailing != null) ...[const SizedBox(width: 4), trailing!],
      ],
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(2, 5, 6, 5),
      decoration: BoxDecoration(color: AppColors.accentSoft, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onTap != null)
            InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: onTap,
              child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), child: labelRow),
            )
          else
            Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), child: labelRow),
          InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: onRemove,
            child: Icon(Icons.close, size: 14, color: AppColors.accent),
          ),
        ],
      ),
    );
  }
}
