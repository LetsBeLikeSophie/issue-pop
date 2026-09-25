import 'package:flutter/material.dart';

import '../theme.dart';

/// 2026-09-25: showModalBottomSheet 호출 8곳이 전부 같은
/// `backgroundColor: AppColors.surface` + 위쪽만 둥근 `shape`를
/// 반복하고 있어서 하나로 뺌.
Future<T?> showAppBottomSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool isScrollControlled = false,
}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    isScrollControlled: isScrollControlled,
    builder: builder,
  );
}

/// 2026-09-25: "제목 + (선택) 부제 + 본문"으로 된 바텀시트 5개
/// (키워드/종목 추가, 발송 내용/오늘의 단어 미리보기, 문의하기)가
/// 여백·타이포까지 동일하게 복붙돼 있어서 하나로 뺌. 시간 선택
/// 시트(_HourPickerSheet)처럼 이 모양이 아닌 것도 있어서, 본문
/// 구조 자체는 그대로 두고 이 틀만 공용화함.
class AppSheetBody extends StatelessWidget {
  const AppSheetBody({super.key, required this.title, this.subtitle, required this.children});

  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.ink)),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle!, style: TextStyle(fontSize: 12, color: AppColors.inkFaint)),
          ],
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}
