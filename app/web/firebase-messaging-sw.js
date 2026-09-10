// 2026-09-08: 웹에서 앱이 백그라운드/닫힌 상태일 때도 푸시 알림을 받으려면
// 필요한 서비스 워커 — firebase_messaging Flutter 패키지가 이 파일을
// 자동으로 등록함(base href 기준 상대 경로). lib/firebase_options.dart와
// 같은 설정값이라 둘 다 바뀌면 여기도 같이 바꿔야 함.

importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyA4Az4lGUp7C08syb7Nvu-GYeKS450S0JE',
  authDomain: 'issue-pop.firebaseapp.com',
  projectId: 'issue-pop',
  storageBucket: 'issue-pop.firebasestorage.app',
  messagingSenderId: '410098193711',
  appId: '1:410098193711:web:82442c2dad96836b8a7dda',
});

firebase.messaging();
