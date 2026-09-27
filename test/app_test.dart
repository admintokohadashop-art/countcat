import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiktok_seller/data/database/app_database.dart';
import 'package:tiktok_seller/data/repositories/account_repository.dart';
import 'package:tiktok_seller/features/dashboard/dashboard_page.dart';

void main() {
  testWidgets('shows the account-selector dashboard initially', (tester) async {
    final testDatabase = AppDatabase.inMemoryForTesting();
    addTearDown(testDatabase.close);
    await testDatabase.database;
    final testRepository = AccountRepository(testDatabase);

    await tester.pumpWidget(MaterialApp(home: DashboardPage(repository: testRepository)));
    await tester.pump();
    await tester.pump();

    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('Create New Account'), findsOneWidget);
  });
}
