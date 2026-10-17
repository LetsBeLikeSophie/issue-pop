import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 2026-10-17: 로딩 화면 아래에 한 줄 팁을 무작위로 보여줌 — 첫 화면을 기다리는 몇 초 동안 앱 기능을 알려주려고.
/// 문구는 실제로 있는 기능만 적을 것(기능이 바뀌면 여기도 같이 고침). 한 번 실행에 하나만 골라서 바뀌지 않게 함.
const launchTips = <String>[
  '이슈 카드를 왼쪽으로 밀면 저장해둘 수 있어요',
  '카드를 누르면 매체별 기사를 바로 펼쳐볼 수 있어요',
  '카드의 이모티콘으로 이 이슈에 대한 내 반응을 남길 수 있어요',
  '관심 키워드를 등록하면 새 이슈가 뜰 때 알려드려요',
  '관심 종목을 설정해보세요',
  '이슈팝 위젯을 설정해보세요',
  '홈 화면 위젯으로 관심 종목 시세를 바로 볼 수 있어요',
  '오늘의 단어 알림을 켜면 매일 새로운 단어를 알려드려요',
  '오늘의 이슈팝 알림으로 매일 정해진 시간에 주요 이슈를 요약해드려요',
  '화면을 아래로 당기면 이슈를 새로고침해요',
  '분야 탭을 옆으로 넘겨서 정치·경제·스포츠 이슈만 모아볼 수 있어요',
  '설정에서 글자 크기와 화면 색을 바꿀 수 있어요',
];

/// 2026-10-13: 앱을 켜고 첫 이슈 목록을 받아오는 동안 보여주는 로딩 화면.
/// 네이티브 스플래시(남색 배경 + 메모장 로고, 정지 화면이라 로딩바를 못 넣음)와
/// 같은 배경/로고/위치로 이어붙여서, 스플래시 → 로딩바 → 앱 화면이 끊김 없이 보이게 함.
/// 테마(화이트/다크)와 무관하게 항상 브랜드 남색.
class LaunchLoading extends StatefulWidget {
  const LaunchLoading({super.key, @visibleForTesting this.tip});

  /// 테스트에서 문구를 고정하려고 열어둠(없으면 launchTips 중 무작위).
  final String? tip;

  static const navy = Color(0xFF17356B);
  static const highlight = Color(0xFFFFD03A);

  @override
  State<LaunchLoading> createState() => _LaunchLoadingState();
}

class _LaunchLoadingState extends State<LaunchLoading> {
  late final String _tip = widget.tip ?? launchTips[Random().nextInt(launchTips.length)];

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: ColoredBox(
        color: LaunchLoading.navy,
        child: Stack(
          children: [
            Center(
              child: SizedBox(
                // 네이티브 스플래시의 이미지 캔버스(288dp)와 같은 크기여야 로고 위치가 안 튐.
                width: 288,
                height: 288,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Image.asset('assets/icon/splash_logo.png', width: 288, height: 288),
                    Positioned(
                      top: 288 / 2 + 92,
                      child: SizedBox(
                        width: 96,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: const LinearProgressIndicator(
                            minHeight: 3,
                            color: LaunchLoading.highlight,
                            backgroundColor: Color(0x33FFFFFF),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // 팁은 로고/로딩바 위치를 건드리지 않게 화면 아래쪽에 따로 둠.
            Positioned(
              left: 32,
              right: 32,
              bottom: MediaQuery.of(context).size.height * 0.14,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: LaunchLoading.highlight,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: const Text(
                      'TIP',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF14161C), letterSpacing: 0.6),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _tip,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.5,
                      color: Color(0xCCFFFFFF),
                      decoration: TextDecoration.none,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
