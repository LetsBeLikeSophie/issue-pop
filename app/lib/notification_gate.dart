import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'device_registry.dart';
import 'push_token.dart';
import 'theme.dart';
import 'widgets/app_bottom_sheet.dart';

/// 2026-10-17: 알림 권한 온보딩 — 알림이 실제로 필요한 동작(알림 켜기, 관심 키워드 등록)을 할 때 한 번 이유를
/// 설명하는 화면을 보여주고, 동의한 뒤에만 OS 권한 팝업을 띄움. 이전에는 설정/관심 키워드/관심 종목 화면에
/// 들어가기만 해도 설명 없이 팝업이 떠서 거부하기 쉬웠고, 한 번 거부하면 기기 설정에서 직접 켜야 해서 복구가 어려움.
///
/// 흐름: 이미 허용 → 바로 true / 아직 안 물어봄 → 설명 시트 → [허용하기]면 OS 팝업 / 이미 거부 → 기기 설정 안내.
/// 거부하거나 "나중에"를 골라도 다시 조르지 않음(호출한 쪽이 알림 없이 계속 진행).
class NotificationGate {
  NotificationGate._();

  // 테스트에서 바꿔 끼우려고 열어둠.
  @visibleForTesting
  static Future<NotificationState> Function() readState = notificationState;
  @visibleForTesting
  static Future<bool> Function(DeviceRegistry) requestPermission = (d) => d.enablePush();
  @visibleForTesting
  static Future<void> Function() openSettings = openNotificationSettings;

  static const _declinedAtKey = 'notification_gate_declined_at_v1';
  static const _quietCooldown = Duration(days: 3);

  /// 알림을 받을 수 있는 상태면 true. [title]/[body]는 "왜 알림이 필요한지"(동작에 맞춰 호출하는 쪽이 정함).
  ///
  /// [quiet]: 사용자가 알림을 직접 켠 게 아니라 다른 일(예: 키워드 등록)을 하다가 곁다리로 묻는 경우 —
  /// 이미 거부했으면 아무 말 없이 false, "나중에"를 골랐으면 3일 동안은 다시 안 물음.
  static Future<bool> ensure(
    BuildContext context,
    DeviceRegistry devices, {
    required String title,
    required String body,
    bool quiet = false,
  }) async {
    final state = await readState();
    if (state == NotificationState.allowed) {
      // 이미 허용된 기기: 진짜 토큰이 서버에 반영돼 있도록 한 번 맞춰둠(팝업은 안 뜸).
      await requestPermission(devices);
      return true;
    }
    if (!context.mounted) return false;

    if (quiet) {
      if (state == NotificationState.denied) return false;
      if (await _declinedRecently()) return false;
      if (!context.mounted) return false;
    }

    if (state == NotificationState.denied) {
      final open = await showAppBottomSheet<bool>(
        context,
        builder: (_) => _GateSheet(
          title: '알림이 꺼져 있어요',
          body: '$body\n\n기기 설정에서 Issue Pop의 알림을 켜면 받을 수 있어요.',
          primary: '설정 열기',
          secondary: '닫기',
        ),
      );
      if (open == true) await openSettings();
      return false;
    }

    if (!context.mounted) return false;
    final ok = await showAppBottomSheet<bool>(
      context,
      builder: (_) => _GateSheet(title: title, body: body, primary: '허용하기', secondary: '나중에'),
    );
    if (ok != true) {
      await _rememberDecline();
      return false;
    }
    return requestPermission(devices);
  }

  static Future<bool> _declinedRecently() async {
    try {
      final at = (await SharedPreferences.getInstance()).getInt(_declinedAtKey);
      if (at == null) return false;
      return DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(at)) < _quietCooldown;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _rememberDecline() async {
    try {
      await (await SharedPreferences.getInstance()).setInt(_declinedAtKey, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {}
  }
}

class _GateSheet extends StatelessWidget {
  const _GateSheet({required this.title, required this.body, required this.primary, required this.secondary});

  final String title;
  final String body;
  final String primary;
  final String secondary;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.notifications_none, size: 20, color: AppColors.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(body, style: TextStyle(fontSize: 13.5, height: 1.5, color: AppColors.inkSoft)),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text(secondary),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
                    child: Text(primary),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
