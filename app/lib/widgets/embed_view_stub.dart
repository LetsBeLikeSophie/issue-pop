import 'package:flutter/widgets.dart';

/// 웹이 아닌 곳에서는 임베드를 지원하지 않음 — false면 호출한 쪽이 링크 버튼으로 대체함.
bool get canEmbed => false;

Widget buildEmbed(String url, double height) => const SizedBox.shrink();
