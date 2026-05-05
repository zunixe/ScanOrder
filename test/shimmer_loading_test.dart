import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scanorder/core/widgets/shimmer_loading.dart';

void main() {
  group('ShimmerLoading', () {
    testWidgets('renders with required dimensions', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ShimmerLoading(width: 100, height: 20),
        ),
      ));
      expect(find.byType(ShimmerLoading), findsOneWidget);
    });

    testWidgets('renders with custom borderRadius', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ShimmerLoading(
            width: 50,
            height: 50,
            borderRadius: BorderRadius.circular(25),
          ),
        ),
      ));
      expect(find.byType(ShimmerLoading), findsOneWidget);
    });
  });

  group('ShimmerScanListItem', () {
    testWidgets('renders', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ShimmerScanListItem(),
        ),
      ));
      expect(find.byType(ShimmerScanListItem), findsOneWidget);
    });
  });

  group('ShimmerCategoryCard', () {
    testWidgets('renders', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ShimmerCategoryCard(),
        ),
      ));
      expect(find.byType(ShimmerCategoryCard), findsOneWidget);
    });
  });

  group('ShimmerStatsCard', () {
    testWidgets('renders', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ShimmerStatsCard(),
        ),
      ));
      expect(find.byType(ShimmerStatsCard), findsOneWidget);
    });
  });
}
