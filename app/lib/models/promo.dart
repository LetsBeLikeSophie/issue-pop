/// 웹(넓은 화면)에서 앱 화면 양옆에 보여주는 홍보 카드 — backend/api.py의 GET /promos와 1:1.
/// "Buy Me a Coffee"와 내 다른 앱 소개 등. 내용은 서버의 backend/promos.json에서 바꿈(앱 재배포 불필요).
class PromoCard {
  const PromoCard({
    required this.id,
    required this.title,
    this.body = '',
    this.button = '',
    this.url = '',
    this.left = false,
    this.highlight = false,
    this.image = '',
    this.embed = '',
    this.embedHeight = 300,
  });

  final String id;
  final String title;
  final String body;

  /// 버튼 글자와 링크는 둘 다 있을 때만 버튼이 생김(없으면 "준비 중" 같은 안내 카드).
  final String button;
  final String url;

  /// 카드 위에 보여줄 이미지(예: 스토어 링크 QR). 없으면 ''.
  final String image;

  /// 페이지 안에 붙여서 보여줄 외부 위젯 주소(예: Buy Me a Coffee 후원 위젯). 웹에서만 쓰이고, 못 쓰면 [url] 버튼으로 대체됨.
  final String embed;
  final double embedHeight;

  /// true면 앱 화면 왼쪽 칸, 아니면 오른쪽 칸.
  final bool left;

  /// 눈에 띄게(채운 버튼) 보여줄지.
  final bool highlight;

  factory PromoCard.fromJson(Map<String, dynamic> json) => PromoCard(
        id: json['id'] as String? ?? '',
        title: json['title'] as String,
        body: json['body'] as String? ?? '',
        button: json['button'] as String? ?? '',
        url: json['url'] as String? ?? '',
        left: json['side'] == 'left',
        highlight: json['highlight'] == true,
        image: json['image'] as String? ?? '',
        embed: json['embed'] as String? ?? '',
        embedHeight: (json['embed_height'] as num?)?.toDouble() ?? 300,
      );

  bool get hasButton => button.isNotEmpty && url.isNotEmpty;
}

/// 서버에서 못 받았을 때(오프라인·서버 점검 등) 보여줄 기본 카드 — 서버 기본값(api._PROMO_DEFAULTS)과 같게 유지.
const kDefaultPromos = <PromoCard>[
  PromoCard(
    id: 'coffee',
    title: 'Buy Me a Coffee',
    body: '이슈팝이 마음에 드셨다면 응원해 주세요. 금액은 직접 정할 수 있어서, 작은 마음도 큰 힘이 돼요.',
    button: '후원하기',
    url: 'https://buymeacoffee.com/itssophie',
    highlight: true,
  ),
];
