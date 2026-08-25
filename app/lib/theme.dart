import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// 디자인 토큰. "이슈판" 프로토타입 아티팩트(클러스터링 검증용으로 먼저
/// 만들었던 신문/에디토리얼 톤)의 배색·레이아웃이 design/ 폴더의 원래
/// "스티커 팝" 와이어프레임보다 낫다는 피드백을 받고, 2026-08-24에
/// 이 팔레트로 전체 교체함. (기존 세이지그린/테라코타 톤은 폐기.)
class AppColors {
  AppColors._();

  static const bg = Color(0xFFEEF1EA);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceAlt = Color(0xFFE4E8DC);
  static const ink = Color(0xFF232A20);
  static const inkSoft = Color(0xFF5C6555);
  static const inkFaint = Color(0xFF8B9280);
  static const accent = Color(0xFF35503F);
  static const accentSoft = Color(0xFFDCE6DD);
  static const accent2 = Color(0xFFA14B2A);
  static const accent2Soft = Color(0xFFF1DED3);
  static const line = Color(0xFFD7DBC9);

  // 구 이름 유지(위젯 코드 전반에서 참조) — 새 팔레트로 매핑.
  static const card = surface;
  static const inkMuted = inkSoft;
  static const chipBg = surfaceAlt;
  static const divider = line;

  static const cardShadow = [
    BoxShadow(color: Color(0x0F232A20), blurRadius: 2, offset: Offset(0, 1)),
    BoxShadow(color: Color(0x0D232A20), blurRadius: 16, offset: Offset(0, 4)),
  ];
}

/// 카테고리별 배지 색. backend/category.py의 CATEGORY_COLORS와 짝을
/// 맞춰뒀음(이슈판 아티팩트와도 동일) — 백엔드가 색을 안 내려주고
/// 카테고리 이름 문자열만 주니까, 여기서 이름→색 매핑을 유지함.
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

  static Color of(String category) => _light[category] ?? _light['기타']!;
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
        brightness: Brightness.light,
        surface: AppColors.bg,
      ),
      textTheme: GoogleFonts.notoSansKrTextTheme(),
    );
    return base.copyWith(
      textTheme: base.textTheme.apply(bodyColor: AppColors.ink, displayColor: AppColors.ink),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.bg,
        foregroundColor: AppColors.ink,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
    );
  }
}
