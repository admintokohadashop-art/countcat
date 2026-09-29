import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiktok_seller/data/models/account.dart';
import 'package:tiktok_seller/data/models/statuses.dart';
import 'package:tiktok_seller/data/models/transaction.dart';
import 'package:tiktok_seller/data/models/transaction_with_order.dart';
import 'package:tiktok_seller/data/repositories/account_repository.dart';
import 'package:tiktok_seller/data/repositories/transaction_repository.dart';
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

  @override
  Future<void> delete(Account account) async {}
}

class _FakeTransactionRepository implements TransactionRepository {
  @override
  Future<int> insertTransaction(Transaction transaction) async => 1;

  @override
  Future<List<Transaction>> listTransactions({
    String search = '',
    int? liveSessionId,
    PaymentStatus? paymentStatus,
    OrderStatus? orderStatus,
    DateTime? periodStart,
    DateTime? periodEnd,
  }) async => const [];

  @override
  Future<void> deleteTransaction(int id) async {}

  @override
  Future<void> updateTransaction(Transaction transaction) async {}

  @override
  Future<List<TransactionWithOrder>> listItemsJoined({
    String search = '',
    int? liveSessionId,
    PaymentStatus? paymentStatus,
    OrderStatus? orderStatus,
    DateTime? periodStart,
    DateTime? periodEnd,
  }) async => const [];

  @override
  Future<void> updateItem(Transaction item) async {}

  @override
  Future<void> deleteItem(int id) async {}
}

void main() {
  testWidgets('shows the account-selector dashboard initially', (tester) async {
    final repository = _FakeAccountRepository();

    await tester.pumpWidget(MaterialApp(
      home: DashboardPage(
        repository: repository,
        transactionRepository: _FakeTransactionRepository(),
      ),
    ));
    await tester.pump();
    await tester.pump();

    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('Create New Account'), findsOneWidget);
  });
}