/// 웹(넓은 화면)에서 앱 화면 양옆에 보여주는 홍보 카드 — backend/api.py의 GET /promos와 1:1.
/// "Buy Me a Coffee"와 내 다른 앱 소개 등. 내용은 서버의 backend/promos.json에서 바꿈(앱 재배포 불필요).
class PromoCard {
  const PromoCard({
    required this.id,
    required this.title,
    required this.body,
    required this.button,
    required this.url,
    this.left = false,
    this.highlight = false,
  });

  final String id;
  final String title;
  final String body;
  final String button;
  final String url;

  /// true면 앱 화면 왼쪽 칸, 아니면 오른쪽 칸.
  final bool left;

  /// 눈에 띄게(채운 버튼) 보여줄지.
  final bool highlight;

  factory PromoCard.fromJson(Map<String, dynamic> json) => PromoCard(
        id: json['id'] as String? ?? '',
        title: json['title'] as String,
        body: json['body'] as String? ?? '',
        button: json['button'] as String,
        url: json['url'] as String,
        left: json['side'] == 'left',
        highlight: json['highlight'] == true,
      );
}

/// 서버에서 못 받았을 때(오프라인·서버 점검 등) 보여줄 기본 카드 — 서버 기본값(api._PROMO_DEFAULTS)과 같게 유지.
const kDefaultPromos = <PromoCard>[
  PromoCard(
    id: 'coffee',
    title: 'Buy Me a Coffee',
    body: '이슈팝이 마음에 드셨다면 커피 한 잔으로 응원해 주세요.',
    button: '후원하기',
    url: 'https://buymeacoffee.com/itssophie',
    highlight: true,
  ),
];
