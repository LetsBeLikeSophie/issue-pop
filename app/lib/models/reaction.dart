import 'package:flutter/material.dart';

/// 카드에 달 수 있는 고정 반응 5개. 서버(backend/api.py의 REACTION_KEYS)에는 이름이
/// 아니라 [key]로 저장되므로, 문구/아이콘을 바꿔도 이미 쌓인 데이터는 그대로 유효함.
/// 리스트 순서는 팝업에 보이는 순서이자(서버의 동률 우선순위와도 같음) 화면 순서.
class ReactionKind {
  const ReactionKind(this.key, this.label, this.icon);

  final String key;
  final String label;
  final IconData icon;
}

const kReactionKinds = <ReactionKind>[
  ReactionKind('like', '좋아요', Icons.sentiment_satisfied_alt),
  ReactionKind('angry', '화나요', Icons.sentiment_very_dissatisfied),
  ReactionKind('worried', '걱정돼요', Icons.warning_amber_rounded),
  ReactionKind('sorry', '안타까워요', Icons.heart_broken_outlined),
  ReactionKind('curious', '궁금해요', Icons.help_outline),
];

ReactionKind? reactionKindOf(String? key) {
  for (final k in kReactionKinds) {
    if (k.key == key) return k;
  }
  return null;
}

/// 카드(대표 키워드) 하나의 반응 집계 — backend/api.py의 /reactions 응답과 1:1.
class ReactionSummary {
  const ReactionSummary({required this.counts, required this.people, required this.top, required this.mine});

  /// 반응 키 → 누른 사람 수(0인 건 없음).
  final Map<String, int> counts;

  /// 반응한 사람 수(한 사람이 하나만 고르므로 counts 합계와 같음).
  final int people;

  /// 가장 많이 눌린 반응 키(아직 없으면 null).
  final String? top;

  /// 이 기기가 고른 반응 키(없으면 null).
  final String? mine;

  static const empty = ReactionSummary(counts: {}, people: 0, top: null, mine: null);

  factory ReactionSummary.fromJson(Map<String, dynamic> json) => ReactionSummary(
        counts: (json['counts'] as Map<String, dynamic>).map((k, v) => MapEntry(k, v as int)),
        people: json['people'] as int,
        top: json['top'] as String?,
        mine: json['mine'] as String?,
      );
}

/// "최근 N분간 M명이 봤어요" — [show]가 false면(서버 기준 최소 인원 미만) 아예 안 보여줌.
class Presence {
  const Presence({required this.online, required this.show, required this.windowMinutes});

  final int online;
  final bool show;
  final int windowMinutes;

  factory Presence.fromJson(Map<String, dynamic> json) => Presence(
        online: json['online'] as int,
        show: json['show'] as bool,
        windowMinutes: json['window_minutes'] as int,
      );
}
