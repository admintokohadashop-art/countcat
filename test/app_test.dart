import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiktok_seller/data/models/account.dart';
import 'package:tiktok_seller/data/repositories/account_repository.dart';
import 'package:tiktok_seller/features/dashboard/dashboard_page.dart';

class _FakeAccountRepository implements AccountRepository {
  @override
  Future<List<Account>> listAccounts() async => const [];

  @override
  Future<Account?> activeAccount() async => null;

  @override
  Future<void> setActiveAccountId(int? id) async {}

  @override
  Future<Account> create({
    required String name,
    String description = '',
    String? photoPath,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<void> update(Account account) async {}
}

void main() {
  testWidgets('shows the account-selector dashboard initially', (tester) async {
    final repository = _FakeAccountRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DashboardPage(repository: repository),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('Create New Account'), findsOneWidget);
  });
}