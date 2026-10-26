import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/widgets.dart';

/// 2026-10-27: 웹에서 외부 위젯(Buy Me a Coffee 후원 폼)을 새 창이 아니라 페이지 안에 iframe으로 붙임.
bool get canEmbed => true;

Widget buildEmbed(String url, double height) {
  return SizedBox(
    height: height,
    child: HtmlElementView.fromTagName(
      tagName: 'iframe',
      onElementCreated: (Object element) {
        final frame = element as JSObject;
        frame.setProperty('src'.toJS, url.toJS);
        frame.setProperty('title'.toJS, '후원 위젯'.toJS);
        frame.setProperty('allow'.toJS, 'payment *'.toJS);
        final style = frame.getProperty<JSObject>('style'.toJS);
        style.setProperty('border'.toJS, 'none'.toJS);
        style.setProperty('width'.toJS, '100%'.toJS);
        style.setProperty('height'.toJS, '100%'.toJS);
        style.setProperty('background'.toJS, 'transparent'.toJS);
      },
    ),
  );
}
