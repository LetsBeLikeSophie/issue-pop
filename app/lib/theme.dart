import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'theme_store.dart';

/// 디자인 토큰. "이슈판" 프로토타입 아티팩트(클러스터링 검증용으로 먼저
/// 만들었던 신문/에디토리얼 톤)의 배색·레이아웃이 design/ 폴더의 원래
/// "스티커 팝" 와이어프레임보다 낫다는 피드백을 받고, 2026-08-24에
/// 이 팔레트로 전체 교체함. (기존 세이지그린/테라코타 톤은 폐기.)
///
/// 2026-09-09: 색 테마 프리셋 추가 — 예전 값들을 "현재" 프리셋으로
/// 그대로 옮기고, 필드를 const에서 getter로 바꿔서 ThemeStore가 고른
/// 프리셋에 따라 런타임에 바뀌게 함. 호출부(`AppColors.ink` 등)는
/// getter든 const든 문법이 똑같아서 안 건드려도 되는데, `const Icon(...,
/// color: AppColors.ink)`처럼 const 컨텍스트 안에서 쓰던 곳들은 더 이상
/// 컴파일타임 상수가 아니라서 그 const만 하나씩 지워야 했음(flutter
/// analyze가 정확히 어디인지 알려줘서 기계적으로 처리함).
class _Palette {
  const _Palette({
    required this.bg,
    required this.surface,
    required this.surfaceAlt,
    required this.ink,
    required this.inkSoft,
    required this.inkFaint,
    required this.accent,
    required this.accentSoft,
    required this.accent2,
    required this.accent2Soft,
    required this.line,
    required this.brightness,
  });

  final Color bg;
  final Color surface;
  final Color surfaceAlt;
  final Color ink;
  final Color inkSoft;
  final Color inkFaint;
  final Color accent;
  final Color accentSoft;
  final Color accent2;
  final Color accent2Soft;
  final Color line;
  final Brightness brightness;
}

const _currentPalette = _Palette(
  bg: Color(0xFFEEF1EA),
  surface: Color(0xFFFFFFFF),
  surfaceAlt: Color(0xFFE4E8DC),
  ink: Color(0xFF232A20),
  inkSoft: Color(0xFF5C6555),
  inkFaint: Color(0xFF8B9280),
  accent: Color(0xFF35503F),
  accentSoft: Color(0xFFDCE6DD),
  accent2: Color(0xFFA14B2A),
  accent2Soft: Color(0xFFF1DED3),
  line: Color(0xFFD7DBC9),
  brightness: Brightness.light,
);

// "흰색(회색 정도)" 요청 — 채도를 거의 빼고 명암 대비로만 위계를 줌.
// accent/accent2는 완전히 같은 회색이면 (관심종목 등가/음가처럼) 색으로
// 구분하던 곳이 안 보이니, 미세하게 톤만 다르게(중성 차콜 vs 따뜻한 톤).
const _neutralPalette = _Palette(
  bg: Color(0xFFF6F6F4),
  surface: Color(0xFFFFFFFF),
  surfaceAlt: Color(0xFFEBEBE7),
  ink: Color(0xFF242422),
  inkSoft: Color(0xFF5F5F5B),
  inkFaint: Color(0xFF8F8F8A),
  accent: Color(0xFF33332F),
  accentSoft: Color(0xFFE7E7E3),
  accent2: Color(0xFF8A6F5C),
  accent2Soft: Color(0xFFEFE7E1),
  line: Color(0xFFDDDDD8),
  brightness: Brightness.light,
);

// 기존 포레스트그린/테라코타 톤을 어두운 배경에 맞게 반전 — 색상 자체는
// 유지해서 "다크"가 별개 브랜드처럼 안 보이게 함.
const _darkPalette = _Palette(
  bg: Color(0xFF1B1F19),
  surface: Color(0xFF242920),
  surfaceAlt: Color(0xFF2C3226),
  ink: Color(0xFFEDEFE7),
  inkSoft: Color(0xFFB7BDAE),
  inkFaint: Color(0xFF838B78),
  accent: Color(0xFF6FA37A),
  accentSoft: Color(0xFF2E3B2C),
  accent2: Color(0xFFD98A63),
  accent2Soft: Color(0xFF3D2E24),
  line: Color(0xFF3A4033),
  brightness: Brightness.dark,
);

const Map<ColorPreset, _Palette> _palettes = {
  ColorPreset.current: _currentPalette,
  ColorPreset.neutral: _neutralPalette,
  ColorPreset.dark: _darkPalette,
};

class AppColors {
  AppColors._();

  static _Palette get _p => _palettes[ThemeStore.instance.preset] ?? _currentPalette;

  static Color get bg => _p.bg;
  static Color get surface => _p.surface;
  static Color get surfaceAlt => _p.surfaceAlt;
  static Color get ink => _p.ink;
  static Color get inkSoft => _p.inkSoft;
  static Color get inkFaint => _p.inkFaint;
  static Color get accent => _p.accent;
  static Color get accentSoft => _p.accentSoft;
  static Color get accent2 => _p.accent2;
  static Color get accent2Soft => _p.accent2Soft;
  static Color get line => _p.line;
  static Brightness get brightness => _p.brightness;

  // 구 이름 유지(위젯 코드 전반에서 참조) — 새 팔레트로 매핑.
  static Color get card => surface;
  static Color get inkMuted => inkSoft;
  static Color get chipBg => surfaceAlt;
  static Color get divider => line;

  static const cardShadow = [
    BoxShadow(color: Color(0x0F000000), blurRadius: 2, offset: Offset(0, 1)),
    BoxShadow(color: Color(0x0D000000), blurRadius: 16, offset: Offset(0, 4)),
  ];

  /// 설정 화면의 테마 선택 스와치용 — 지금 선택된 프리셋이 아니라 [preset]
  /// 자체의 색을 미리보기로 보여줘야 해서, 현재 프리셋과 무관하게 조회함.
  static (Color bg, Color accent, Color accent2) previewColors(ColorPreset preset) {
    final p = _palettes[preset] ?? _currentPalette;
    return (p.bg, p.accent, p.accent2);
  }
}

/// 카테고리별 배지 색. backend/category.py의 CATEGORY_COLORS와 짝을
/// 맞춰뒀음(이슈판 아티팩트와도 동일) — 백엔드가 색을 안 내려주고
/// 카테고리 이름 문자열만 주니까, 여기서 이름→색 매핑을 유지함.
///
/// 2026-09-09: 다크 프리셋에서도 그대로 쓰면 어두운 배경 위에서 채도
/// 낮은 원래 색은 잘 안 보여서, 프리셋이 dark일 때는 살짝 밝힌 버전을
/// 따로 둠(카테고리 색 자체의 정체성은 유지, 명도만 다크 배경에 맞춤).
class CategoryColors {
  CategoryColors._();

  static const Map<String, Color> _light = {
    '정치': Color(0xFF5B6BB0),
    '경제': Color(0xFFA17A1F),
    '사회': Color(0xFF7A5BA0),
    '국제': Color(0xFF3F8F8A),
    '스포츠': Color(0xFF4A8A4F),
    '연예': Color(0xFFC04F7D),
    'IT/과학': Color(0xFF3D6FA8),
    '문화': Color(0xFFB3623A),
    '기타': Color(0xFF7A7F6F),
  };

  static const Map<String, Color> _dark = {
    '정치': Color(0xFF8B9AE0),
    '경제': Color(0xFFD1A84F),
    '사회': Color(0xFFAA8BD0),
    '국제': Color(0xFF6FBFB9),
    '스포츠': Color(0xFF7AB97F),
    '연예': Color(0xFFE07FA5),
    'IT/과학': Color(0xFF6D9FD8),
    '문화': Color(0xFFE0925F),
    '기타': Color(0xFFA7ACA0),
  };

  static Color of(String category) {
    final table = ThemeStore.instance.preset == ColorPreset.dark ? _dark : _light;
    return table[category] ?? table['기타']!;
  }
}

/// 카테고리 표시 순서(카테고리 필터 칩 등에서 씀) — backend/category.py의
/// CATEGORY_KEYWORDS 정의 순서와 맞춤. "문화"는 2026-08-24에 새로 추가됨.
const kCategoryOrder = ['정치', '경제', '사회', '국제', '스포츠', '연예', 'IT/과학', '문화', '기타'];

class AppTypography {
  AppTypography._();

  /// 대표/보조 키워드 전용 세리프. 나머지는 전부 Noto Sans KR로 통일.
  static TextStyle serif({
    required double fontSize,
    required FontWeight fontWeight,
    Color? color,
  }) =>
      GoogleFonts.notoSerifKr(fontSize: fontSize, fontWeight: fontWeight, color: color);
}

class AppTheme {
  AppTheme._();

  static ThemeData get light {
    final base = ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.bg,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.accent,
        brightness: AppColors.brightness,
        surface: AppColors.bg,
      ),
      textTheme: GoogleFonts.notoSansKrTextTheme(),
    );
    return base.copyWith(
      textTheme: base.textTheme.apply(bodyColor: AppColors.ink, displayColor: AppColors.ink),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.bg,
        foregroundColor: AppColors.ink,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
    );
  }
}
