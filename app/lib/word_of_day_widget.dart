import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';

import 'api_client.dart';

/// 2026-09-27: 홈 화면 "오늘의 단어" 위젯 — 작게, 오늘의 단어 + 짧은
/// 뜻풀이만 보여줌. 뉴스 목록처럼 자주 갱신할 필요가 없어서(하루 한
/// 번만 바뀜) 안드로이드 위젯 표준 정기 갱신(word_of_day_widget_info.xml,
/// 6시간)만으로 충분함 — 별도 서버 API도 새로 안 만들고, 설정 화면
/// 미리보기가 이미 쓰는 GET /word-of-day를 그대로 재사용함.
///
/// 웹은 홈 화면 위젯 개념이 없어서(kIsWeb) 아무것도 안 함. 실제
/// AppWidgetProvider는 WordOfDayWidgetProvider.kt 참고.
const _androidWidgetName = 'WordOfDayWidgetProvider';
const _highlightColorKey = 'word_of_day_highlight_color_index';
const _imageKey = 'word_of_day_image';

/// 위젯을 처음 추가할 때(WordOfDayWidgetConfigureActivity.kt) 하나
/// 고르게 하는 형광펜 색 3가지 — 로고와 같은 옐로우가 기본.
const highlightColors = <Color>[
  Color(0xFFF4C94E), // 옐로우 (기본, 앱 로고와 같은 색)
  Color(0xFFA8D8B9), // 민트
  Color(0xFFC7D2F0), // 라벤더
];

Future<void> updateWordOfDayWidget(ApiClient api) async {
  if (kIsWeb) return;
  try {
    final wordOfDay = await api.getWordOfDay();
    final colorIndex = await HomeWidget.getWidgetData<int>(_highlightColorKey, defaultValue: 0) ?? 0;
    final color = highlightColors[colorIndex.clamp(0, highlightColors.length - 1)];

    await HomeWidget.saveWidgetData(
      'word_of_day_definition',
      wordOfDay.definition ?? '오늘의 단어를 아직 못 받아왔어요',
    );
    await HomeWidget.renderFlutterWidget(
      _HighlightedWord(word: wordOfDay.word ?? '이슈판을 열어보세요', color: color),
      key: _imageKey,
      logicalSize: const Size(260, 56),
      pixelRatio: 3,
    );
    await HomeWidget.updateWidget(androidName: _androidWidgetName);
  } catch (_) {
    // 위젯 갱신 실패는 조용히 무시 — 다음 정기 갱신 때 다시 시도됨.
  }
}

/// OS가 위젯 정기 갱신 때(WordOfDayWidgetProvider.onUpdate) 또는 색을
/// 막 고른 직후(WordOfDayWidgetConfigureActivity) 헤드리스 플러터
/// 엔진으로 깨우는 콜백 — 앱이 안 켜져 있어도 여기서 새 단어를 받아와
/// 위젯에 반영함. main()에서 registerInteractivityCallback으로 한 번
/// 등록해둬야 네이티브가 이 핸들을 기억해뒀다가 나중에 부를 수 있음.
@pragma('vm:entry-point')
Future<void> wordOfDayBackgroundCallback(Uri? uri) async {
  await updateWordOfDayWidget(ApiClient());
}

/// 로고의 "Pop" 형광펜 효과(home_screen.dart)와 같은 방식 — 글자 아래쪽
/// 절반 정도에만 색 배경을 깔아서 실제 형광펜처럼 보이게 함.
/// renderFlutterWidget()으로 PNG 이미지 파일로 저장되고, 네이티브
/// RemoteViews(위젯)는 이 PNG를 ImageView에 그대로 얹기만 함 — 이
/// 하이라이트 효과 자체는 순수 RemoteViews로는 표현할 수 없어서
/// 이미지로 미리 그려서 넘기는 방식을 씀.
class _HighlightedWord extends StatelessWidget {
  const _HighlightedWord({required this.word, required this.color});

  final String word;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.white,
      child: Stack(
        alignment: Alignment.bottomLeft,
        children: [
          Positioned.fill(
            child: Align(
              alignment: Alignment.bottomLeft,
              child: FractionallySizedBox(
                heightFactor: 0.42,
                widthFactor: 1,
                child: ColoredBox(color: color),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              word,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: Color(0xFF14161C)),
            ),
          ),
        ],
      ),
    );
  }
}
