/// backend/api.py의 IssueSummary와 1:1로 맞춘 모델.
class IssueSummary {
  final String id;
  final String keyword;
  final List<String> keywords;
  final String category;
  final String representativeTitle;
  final int articleCount;
  final int outletCount;

  /// 2026-09-08: "N일째 보도 중" 배지용 — 이 이슈 id가 DB에 처음 잡힌
  /// 시각. 일별 보도량 히스토리는 없어서(추이 그래프 대신 이 배지만
  /// 씀) 진짜 "추이"는 아니고 지속 기간만 보여줌.
  final DateTime? firstSeenAt;

  /// 2026-09-20: 정치성향 필터용 — 이 이슈에 기여한 매체들의 성향을 중복
  /// 제거해서 모은 목록(예: ["보수","진보"]). 즐겨찾기/아카이브처럼 DB에서
  /// 바로 읽어오는 경로는 매체별 breakdown이 없어서 빈 배열로 옴 — 그
  /// 경로는 애초에 이 필터를 쓰는 화면이 아님.
  final List<String> leanings;

  IssueSummary({
    required this.id,
    required this.keyword,
    required this.keywords,
    required this.category,
    required this.representativeTitle,
    required this.articleCount,
    required this.outletCount,
    this.firstSeenAt,
    this.leanings = const [],
  });

  factory IssueSummary.fromJson(Map<String, dynamic> json) => IssueSummary(
        id: json['id'] as String,
        keyword: json['keyword'] as String,
        keywords: (json['keywords'] as List).cast<String>(),
        category: json['category'] as String,
        representativeTitle: json['representative_title'] as String,
        articleCount: json['article_count'] as int,
        outletCount: json['outlet_count'] as int,
        firstSeenAt: json['first_seen_at'] == null ? null : DateTime.tryParse(json['first_seen_at'] as String),
        leanings: json['leanings'] == null ? const [] : (json['leanings'] as List).cast<String>(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'keyword': keyword,
        'keywords': keywords,
        'category': category,
        'representative_title': representativeTitle,
        'article_count': articleCount,
        'outlet_count': outletCount,
        'first_seen_at': firstSeenAt?.toIso8601String(),
        'leanings': leanings,
      };
}

/// backend/api.py의 OutletLeaningInfo — 정치성향 필터 안내 모달용.
/// sources.py RSS_SOURCES를 그대로 노출하는 것이라 매체가 늘거나
/// leaning_source가 갱신되면 이 모델도 별도 변경 없이 그대로 반영됨.
class OutletLeaningInfo {
  final String outlet;
  final String category;
  final String? politicalLeaning;
  final String? leaningSource;
  final String? leaningUpdated;

  OutletLeaningInfo({
    required this.outlet,
    required this.category,
    this.politicalLeaning,
    this.leaningSource,
    this.leaningUpdated,
  });

  factory OutletLeaningInfo.fromJson(Map<String, dynamic> json) => OutletLeaningInfo(
        outlet: json['outlet'] as String,
        category: json['category'] as String,
        politicalLeaning: json['political_leaning'] as String?,
        leaningSource: json['leaning_source'] as String?,
        leaningUpdated: json['leaning_updated'] as String?,
      );
}

class OutletBreakdown {
  final String outlet;
  final int count;

  /// 2026-09-20: 이 매체의 정치성향(sources.py OUTLET_LEANING 기준).
  /// 미분류 매체는 null — 성향 필터에서 이 매체는 제외됨.
  final String? leaning;

  OutletBreakdown({required this.outlet, required this.count, this.leaning});

  factory OutletBreakdown.fromJson(Map<String, dynamic> json) => OutletBreakdown(
        outlet: json['outlet'] as String,
        count: json['count'] as int,
        leaning: json['leaning'] as String?,
      );

  Map<String, dynamic> toJson() => {'outlet': outlet, 'count': count, 'leaning': leaning};
}

class ArticleOut {
  final String outlet;
  final String title;
  final String link;
  final String? published;

  /// 2026-09-07: 기사 썸네일 — 매체마다 있는 곳/없는 곳이 섞여 있어서
  /// (연합뉴스는 대부분 있음, 경향신문은 거의 없음, 실측 확인) null이면
  /// 그냥 썸네일 없이 텍스트만 보여주면 됨(fetcher.py의 _extract_image).
  final String? image;

  ArticleOut({required this.outlet, required this.title, required this.link, this.published, this.image});

  factory ArticleOut.fromJson(Map<String, dynamic> json) => ArticleOut(
        outlet: json['outlet'] as String,
        title: json['title'] as String,
        link: json['link'] as String,
        published: json['published'] as String?,
        image: json['image'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'outlet': outlet,
        'title': title,
        'link': link,
        'published': published,
        'image': image,
      };
}

/// backend/api.py의 IssueDetail (IssueSummary + outlets + articles).
class IssueDetail extends IssueSummary {
  final List<OutletBreakdown> outlets;
  final List<ArticleOut> articles;

  IssueDetail({
    required super.id,
    required super.keyword,
    required super.keywords,
    required super.category,
    required super.representativeTitle,
    required super.articleCount,
    required super.outletCount,
    super.firstSeenAt,
    super.leanings,
    required this.outlets,
    required this.articles,
  });

  factory IssueDetail.fromJson(Map<String, dynamic> json) => IssueDetail(
        id: json['id'] as String,
        keyword: json['keyword'] as String,
        keywords: (json['keywords'] as List).cast<String>(),
        category: json['category'] as String,
        representativeTitle: json['representative_title'] as String,
        articleCount: json['article_count'] as int,
        outletCount: json['outlet_count'] as int,
        firstSeenAt: json['first_seen_at'] == null ? null : DateTime.tryParse(json['first_seen_at'] as String),
        leanings: json['leanings'] == null ? const [] : (json['leanings'] as List).cast<String>(),
        outlets: (json['outlets'] as List)
            .map((e) => OutletBreakdown.fromJson(e as Map<String, dynamic>))
            .toList(),
        articles: (json['articles'] as List)
            .map((e) => ArticleOut.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  @override
  Map<String, dynamic> toJson() => {
        ...super.toJson(),
        'outlets': outlets.map((o) => o.toJson()).toList(),
        'articles': articles.map((a) => a.toJson()).toList(),
      };
}
