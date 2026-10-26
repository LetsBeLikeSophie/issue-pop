// 웹에서는 iframe으로 외부 위젯을 페이지 안에 붙이고, 그 밖(앱·테스트)에서는 아무것도 그리지 않음(호출한 쪽이 링크 버튼으로 대체).
export 'embed_view_stub.dart' if (dart.library.js_interop) 'embed_view_web.dart';
