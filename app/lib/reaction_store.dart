import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'install_id.dart';
import 'models/reaction.dart';

enum ReactionSetResult { ok, issueGone, failed }

/// 2026-10-13: 카드(대표 키워드)별 반응을 앱 전체에서 하나로 들고 있는 저장소.
/// 카드 수십~수백 개가 각자 서버를 부르지 않도록, 보이는 카드들이 [watch]를 부르면
/// 잠깐 모았다가 한 번에(최대 80개씩) 묻는다. 반응을 정하면 서버가 돌려주는 최신
/// 집계로 그 카드만 갱신함.
class ReactionStore {
  ReactionStore._();

  static final ReactionStore instance = ReactionStore._();

  static const _batchSize = 80;
  static const _retryCooldown = Duration(seconds: 30);

  ApiClient? _api;
  final _notifiers = <String, ValueNotifier<ReactionSummary?>>{};
  final _requested = <String>{};
  final _queue = <String>{};
  Timer? _flushTimer;
  DateTime? _lastFailureAt;

  void init(ApiClient api) => _api = api;

  /// 싱글턴이라 테스트끼리 상태(대기 중인 타이머, 받아둔 집계)가 새지 않게 비움.
  @visibleForTesting
  void resetForTest() {
    _flushTimer?.cancel();
    _flushTimer = null;
    _notifiers.clear();
    _requested.clear();
    _queue.clear();
    _lastFailureAt = null;
  }

  /// 이 키워드 카드의 반응 집계(아직 못 받았으면 null). 처음 부르면 조회를 예약함.
  ValueListenable<ReactionSummary?> watch(String keyword) {
    final notifier = _notifiers.putIfAbsent(keyword, () => ValueNotifier<ReactionSummary?>(null));
    if (notifier.value == null && !_requested.contains(keyword)) {
      final failedAt = _lastFailureAt;
      if (failedAt == null || DateTime.now().difference(failedAt) > _retryCooldown) {
        _requested.add(keyword);
        _queue.add(keyword);
        _scheduleFlush();
      }
    }
    return notifier;
  }

  /// 당겨서 새로고침할 때 — 이미 본 카드들의 집계를 다시 받아옴.
  void refreshAll() {
    _queue.addAll(_notifiers.keys);
    _requested.addAll(_notifiers.keys);
    _scheduleFlush();
  }

  void _scheduleFlush() {
    _flushTimer ??= Timer(const Duration(milliseconds: 80), _flush);
  }

  Future<void> _flush() async {
    _flushTimer = null;
    final api = _api;
    if (api == null || _queue.isEmpty) return;
    final keywords = _queue.toList();
    _queue.clear();
    final clientId = await InstallId.get();
    for (var i = 0; i < keywords.length; i += _batchSize) {
      final chunk = keywords.sublist(i, min(i + _batchSize, keywords.length));
      try {
        final result = await api.getReactions(chunk, clientId);
        for (final entry in result.entries) {
          _notifiers[entry.key]?.value = entry.value;
        }
      } catch (_) {
        _lastFailureAt = DateTime.now();
        _requested.removeAll(chunk);
      }
    }
  }

  /// 내 반응을 [reaction](키)으로 정함. 이미 같은 걸 골랐으면 취소(null)로 보냄.
  /// 성공하면 서버가 돌려준 최신 집계로 그 카드를 갱신함.
  Future<ReactionSetResult> choose(String keyword, String reaction) async {
    final current = _notifiers[keyword]?.value?.mine;
    return _send(keyword, current == reaction ? null : reaction);
  }

  Future<ReactionSetResult> _send(String keyword, String? reaction) async {
    final api = _api;
    if (api == null) return ReactionSetResult.failed;
    try {
      final clientId = await InstallId.get();
      final summary = await api.setReaction(clientId: clientId, keyword: keyword, reaction: reaction);
      _notifiers.putIfAbsent(keyword, () => ValueNotifier<ReactionSummary?>(null)).value = summary;
      _requested.add(keyword);
      return ReactionSetResult.ok;
    } on ApiException catch (e) {
      return e.statusCode == 404 ? ReactionSetResult.issueGone : ReactionSetResult.failed;
    } catch (_) {
      return ReactionSetResult.failed;
    }
  }
}
