import 'package:flutter/material.dart';

import 'api_client.dart';
import 'screens/home_screen.dart';
import 'theme.dart';

void main() {
  runApp(const IssuePopApp());
}

class IssuePopApp extends StatelessWidget {
  const IssuePopApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '뉴스 트렌드',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: HomeScreen(api: ApiClient()),
    );
  }
}
