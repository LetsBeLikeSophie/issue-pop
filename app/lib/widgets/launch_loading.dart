import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 2026-10-13: 앱을 켜고 첫 이슈 목록을 받아오는 동안 보여주는 로딩 화면.
/// 네이티브 스플래시(남색 배경 + 메모장 로고, 정지 화면이라 로딩바를 못 넣음)와
/// 같은 배경/로고/위치로 이어붙여서, 스플래시 → 로딩바 → 앱 화면이 끊김 없이 보이게 함.
/// 테마(화이트/다크)와 무관하게 항상 브랜드 남색.
class LaunchLoading extends StatelessWidget {
  const LaunchLoading({super.key});

  static const navy = Color(0xFF17356B);
  static const highlight = Color(0xFFFFD03A);

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: ColoredBox(
        color: navy,
        child: Center(
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
                        color: highlight,
                        backgroundColor: Color(0x33FFFFFF),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
