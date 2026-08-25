/// backend/api.py의 IssueSummary와 1:1로 맞춘 모델.
class IssueSummary {
  final String id;
  final String keyword;
  final List<String> keywords;
  final String category;
  final String representativeTitle;
  final int articleCount;
  final int outletCount;

  IssueSummary({
    required this.id,
    required this.keyword,
    required this.keywords,
    required this.category,
    required this.representativeTitle,
    required this.articleCount,
    required this.outletCount,
  });

  factory IssueSummary.fromJson(Map<String, dynamic> json) => IssueSummary(
        id: json['id'] as String,
        keyword: json['keyword'] as String,
        keywords: (json['keywords'] as List).cast<String>(),
        category: json['category'] as String,
        representativeTitle: json['representative_title'] as String,
        articleCount: json['article_count'] as int,
        outletCount: json['outlet_count'] as int,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'keyword': keyword,
        'keywords': keywords,
        'category': category,
        'representative_title': representativeTitle,
        'article_count': articleCount,
        'outlet_count': outletCount,
      };
}

class OutletBreakdown {
  final String outlet;
  final int count;

  OutletBreakdown({required this.outlet, required this.count});

  factory OutletBreakdown.fromJson(Map<String, dynamic> json) =>
      OutletBreakdown(outlet: json['outlet'] as String, count: json['count'] as int);

  Map<String, dynamic> toJson() => {'outlet': outlet, 'count': count};
}

class ArticleOut {
  final String outlet;
  final String title;
  final String link;
  final String? published;

  ArticleOut({required this.outlet, required this.title, required this.link, this.published});

  factory ArticleOut.fromJson(Map<String, dynamic> json) => ArticleOut(
        outlet: json['outlet'] as String,
        title: json['title'] as String,
        link: json['link'] as String,
        published: json['published'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'outlet': outlet,
        'title': title,
        'link': link,
        'published': published,
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
