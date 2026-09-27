import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiktok_seller/data/database/app_database.dart';
import 'package:tiktok_seller/data/models/account.dart';
import 'package:tiktok_seller/data/repositories/account_repository.dart';
import 'package:tiktok_seller/features/dashboard/dashboard_page.dart';

class _FakeAccountRepository extends AccountRepository {
  _FakeAccountRepository() : super(AppDatabase.inMemoryForTesting());

  @override
  Future<List<Account>> listAccounts() async => const [];

  @override
  Future<Account?> activeAccount() async => null;
}

void main() {
  testWidgets('shows the account-selector dashboard initially', (tester) async {
    final repository = _FakeAccountRepository();

    await tester.pumpWidget(MaterialApp(home: DashboardPage(repository: repository)));
    await tester.pump();
    await tester.pump();

    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('Create New Account'), findsOneWidget);
  });
}
