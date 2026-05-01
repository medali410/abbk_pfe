import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:network_image_mock/network_image_mock.dart';

import 'package:dali_pfe/main.dart';

void main() {
  testWidgets('MyApp démarre (smoke)', (WidgetTester tester) async {
    await mockNetworkImagesFor(() async {
      await tester.pumpWidget(const MyApp());
      await tester.pump();
      expect(find.byType(MaterialApp), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
    });
  });
}
