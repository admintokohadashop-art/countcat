import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiktok_seller/data/models/account.dart';
import 'package:tiktok_seller/data/models/hpp_master.dart';
import 'package:tiktok_seller/data/models/live_session.dart';
import 'package:tiktok_seller/data/models/statuses.dart';
import 'package:tiktok_seller/data/models/transaction.dart';
import 'package:tiktok_seller/data/repositories/account_repository.dart';
import 'package:tiktok_seller/data/repositories/hpp_repository.dart';
import 'package:tiktok_seller/data/repositories/live_session_repository.dart';
import 'package:tiktok_seller/data/repositories/transaction_repository.dart';
import 'package:tiktok_seller/features/sales/new_sale_page.dart';

class _FakeAccountRepository implements AccountRepository {
  @override
  Future<List<Account>> listAccounts() async => const [];
  @override
  Future<Account?> activeAccount() async {
    final now = DateTime(2026);
    return Account(id: 1, name: 'Main', description: '', createdAt: now, updatedAt: now);
  }
  @override
  Future<void> setActiveAccountId(int? id) async {}
  @override
  Future<Account> create({required String name, String description = '', String? photoPath}) async => throw UnimplementedError();
  @override
  Future<void> update(Account account) async {}
}

class _FakeLiveSessionRepository implements LiveSessionRepository {
  @override
  Future<LiveSession> createSession({required String name, DateTime? startedAt}) async => throw UnimplementedError();
  @override
  Future<List<LiveSession>> listSessions() async => const [];
  @override
  Future<int?> getSelectedSessionId() async => null;
  @override
  Future<void> setSelectedSessionId(int? sessionId) async {}
  @override
  Future<LiveSession?> getSelectedSession() async => null;
}

class _FakeHppRepository implements HppRepository {
  _FakeHppRepository(this._items);
  final List<HppMaster> _items;
  @override
  Future<List<HppMaster>> list(int accountId, {bool activeOnly = true}) async => _items;
  @override
  Future<HppMaster?> find(int? id) async {
    for (final h in _items) {
      if (h.id == id) return h;
    }
    return null;
  }
  @override
  Future<HppMaster> create({required int accountId, required String name, required int unitAmount}) async => throw UnimplementedError();
  @override
  Future<void> update(HppMaster h) async {}
  @override
  Future<void> deactivate(int id, int accountId) async {}
}

class _FakeTransactionRepository implements TransactionRepository {
  Transaction? lastInserted;
  @override
  Future<int> insertTransaction(Transaction transaction) async {
    lastInserted = transaction;
    return 1;
  }
  @override
  Future<List<Transaction>> listTransactions({String search = '', int? liveSessionId, PaymentStatus? paymentStatus, OrderStatus? orderStatus, DateTime? periodStart, DateTime? periodEnd}) async => const [];
  @override
  Future<void> deleteTransaction(int id) async {}
  @override
  Future<void> updateTransaction(Transaction transaction) async {}
}

HppMaster _hpp({int id = 10, int amount = 20000, String name = 'Cardigan'}) {
  final now = DateTime(2026);
  return HppMaster(id: id, accountId: 1, name: name, unitAmount: amount, isActive: true, createdAt: now, updatedAt: now);
}

Future<void> _pumpPage(
  WidgetTester tester, {
  required _FakeHppRepository hppRepo,
  required _FakeTransactionRepository txRepo,
}) async {
  tester.view.physicalSize = const Size(1000, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: NewSalePage(
        accountRepository: _FakeAccountRepository(),
        liveSessionRepository: _FakeLiveSessionRepository(),
        hppRepository: hppRepo,
        transactionRepository: txRepo,
      ),
    ),
  ));
  await tester.pump();
  await tester.pump();
}

Future<void> _enter(WidgetTester tester, String label, String text) async {
  await tester.enterText(find.widgetWithText(TextFormField, label), text);
  await tester.pump();
}

Future<void> _selectField<T>(WidgetTester tester, String label, T value) async {
  final finder = find
      .ancestor(
        of: find.text(label),
        matching: find.byType(DropdownButtonFormField<T>),
      )
      .first;
  final state = tester.state<FormFieldState<T>>(finder);
  state.didChange(value);
  await tester.pump();
}

Future<void> _submit(WidgetTester tester) async {
  await tester.ensureVisible(find.text('SUBMIT'));
  await tester.pump();
  await tester.tap(find.text('SUBMIT'));
  await tester.pump();
  await tester.pump();
  await tester.pump();
}

Finder _readOnlyField(String label) => find.byWidgetPredicate(
      (w) => w is InputDecorator && w.decoration.labelText == label,
    );

Finder _textFormFieldByLabel(String label) => find.ancestor(
      of: find.text(label),
      matching: find.byType(TextFormField),
    );

void main() {
  testWidgets('Qty 1 and Harga Jual 50.000 produces GMV Rp50.000', (tester) async {
    await _pumpPage(tester, hppRepo: _FakeHppRepository([_hpp()]), txRepo: _FakeTransactionRepository());
    await _enter(tester, 'Harga Jual', '50000');
    await _enter(tester, 'Qty', '1');
    expect(find.text('Rp50.000'), findsOneWidget);
  });

  testWidgets('Qty 2 and Harga Jual 50.000 produces GMV Rp100.000', (tester) async {
    await _pumpPage(tester, hppRepo: _FakeHppRepository([_hpp()]), txRepo: _FakeTransactionRepository());
    await _enter(tester, 'Harga Jual', '50000');
    await _enter(tester, 'Qty', '2');
    expect(find.text('Rp100.000'), findsOneWidget);
  });

  testWidgets('changing Harga Jual recomputes GMV', (tester) async {
    await _pumpPage(tester, hppRepo: _FakeHppRepository([_hpp()]), txRepo: _FakeTransactionRepository());
    await _enter(tester, 'Qty', '2');
    await _enter(tester, 'Harga Jual', '50000');
    expect(find.text('Rp100.000'), findsOneWidget);
    await _enter(tester, 'Harga Jual', '60000');
    expect(find.text('Rp120.000'), findsOneWidget);
    expect(find.text('Rp100.000'), findsNothing);
  });

  testWidgets('changing Qty recomputes GMV', (tester) async {
    await _pumpPage(tester, hppRepo: _FakeHppRepository([_hpp()]), txRepo: _FakeTransactionRepository());
    await _enter(tester, 'Harga Jual', '50000');
    await _enter(tester, 'Qty', '2');
    expect(find.text('Rp100.000'), findsOneWidget);
    await _enter(tester, 'Qty', '3');
    expect(find.text('Rp150.000'), findsOneWidget);
  });

  testWidgets('when HPP not selected, Profit shows Rp0 even after Income is typed', (tester) async {
    await _pumpPage(tester, hppRepo: _FakeHppRepository([_hpp()]), txRepo: _FakeTransactionRepository());
    await _enter(tester, 'Income', '46000');
    await _enter(tester, 'Qty', '2');
    final profitField = _readOnlyField('Profit');
    expect(profitField, findsOneWidget);
    expect(find.descendant(of: profitField, matching: find.text('Rp0')), findsOneWidget);
  });

  testWidgets('Profit recomputes when Income changes (HPP selected)', (tester) async {
    await _pumpPage(tester, hppRepo: _FakeHppRepository([_hpp(amount: 20000)]), txRepo: _FakeTransactionRepository());
    await _enter(tester, 'Qty', '2');
    await _selectField<int>(tester, 'HPP', 10);
    await _enter(tester, 'Income', '46000');
    expect(find.text('Rp6.000'), findsOneWidget);
    await _enter(tester, 'Income', '50000');
    expect(find.text('Rp10.000'), findsOneWidget);
  });

  testWidgets('Profit recomputes when Qty changes (HPP selected)', (tester) async {
    await _pumpPage(tester, hppRepo: _FakeHppRepository([_hpp(amount: 20000)]), txRepo: _FakeTransactionRepository());
    await _selectField<int>(tester, 'HPP', 10);
    await _enter(tester, 'Income', '46000');
    await _enter(tester, 'Qty', '1');
    expect(find.text('Rp26.000'), findsOneWidget);
    await _enter(tester, 'Qty', '2');
    expect(find.text('Rp6.000'), findsOneWidget);
  });

  testWidgets('Profit recomputes when HPP changes', (tester) async {
    await _pumpPage(
      tester,
      hppRepo: _FakeHppRepository([
        _hpp(id: 10, amount: 20000, name: 'Cardigan'),
        _hpp(id: 11, amount: 25000, name: 'Blouse'),
      ]),
      txRepo: _FakeTransactionRepository(),
    );
    await _enter(tester, 'Qty', '2');
    await _enter(tester, 'Income', '46000');
    await _selectField<int>(tester, 'HPP', 10);
    expect(find.text('Rp6.000'), findsOneWidget);
    await _selectField<int>(tester, 'HPP', 11);
    // Rupiah.format renders negatives as "Rp-4.000" (prefix "Rp", then the
    // signed number). This matches production behavior; no formatter change.
    expect(find.text('Rp-4.000'), findsOneWidget);
  });

  testWidgets('GMV field is read-only (no EditableText inside)', (tester) async {
    await _pumpPage(tester, hppRepo: _FakeHppRepository([_hpp()]), txRepo: _FakeTransactionRepository());
    final gmvField = _readOnlyField('GMV');
    expect(gmvField, findsOneWidget);
    expect(find.descendant(of: gmvField, matching: find.byType(EditableText)), findsNothing);
  });

  testWidgets('Profit field is read-only (no EditableText inside)', (tester) async {
    await _pumpPage(tester, hppRepo: _FakeHppRepository([_hpp()]), txRepo: _FakeTransactionRepository());
    final profitField = _readOnlyField('Profit');
    expect(profitField, findsOneWidget);
    expect(find.descendant(of: profitField, matching: find.byType(EditableText)), findsNothing);
  });

  testWidgets('Harga Jual = 0 blocks submit and shows validation error', (tester) async {
    await _pumpPage(tester, hppRepo: _FakeHppRepository([_hpp()]), txRepo: _FakeTransactionRepository());
    await _enter(tester, 'Kode Barang', 'SKU');
    await _enter(tester, 'ID Pesanan', 'ORD');
    await _enter(tester, 'Qty', '1');
    await _enter(tester, 'Harga Jual', '0');
    await _enter(tester, 'Income', '1000');
    await _selectField<int>(tester, 'HPP', 10);
    await _submit(tester);
    // The same message is also shown in a SnackBar; scope the assertion to the
    // inline error rendered inside the Harga Jual field.
    final hargaJualField = _textFormFieldByLabel('Harga Jual');
    expect(hargaJualField, findsOneWidget);
    expect(find.descendant(of: hargaJualField, matching: find.text('Harga Jual harus lebih dari 0.')), findsOneWidget);
  });

  testWidgets('missing HPP blocks submit', (tester) async {
    final txRepo = _FakeTransactionRepository();
    await _pumpPage(tester, hppRepo: _FakeHppRepository([_hpp()]), txRepo: txRepo);
    await _enter(tester, 'Kode Barang', 'SKU');
    await _enter(tester, 'ID Pesanan', 'ORD');
    await _enter(tester, 'Qty', '1');
    await _enter(tester, 'Harga Jual', '50000');
    await _enter(tester, 'Income', '46000');
    await _submit(tester);
    expect(txRepo.lastInserted, isNull);
    expect(find.text('HPP wajib dipilih.'), findsOneWidget);
  });

  testWidgets('submit persists unitPrice and derived gmvAmount', (tester) async {
    final txRepo = _FakeTransactionRepository();
    await _pumpPage(tester, hppRepo: _FakeHppRepository([_hpp(amount: 20000)]), txRepo: txRepo);
    await _enter(tester, 'Kode Barang', 'SKU');
    await _enter(tester, 'ID Pesanan', 'ORD');
    await _enter(tester, 'Qty', '2');
    await _enter(tester, 'Harga Jual', '50000');
    await _enter(tester, 'Income', '46000');
    await _selectField<int>(tester, 'HPP', 10);
    await _submit(tester);
    final inserted = txRepo.lastInserted;
    expect(inserted, isNotNull);
    expect(inserted!.unitPrice, 50000);
    expect(inserted.quantity, 2);
    expect(inserted.gmvAmount, 100000);
    expect(inserted.netIncomeAmount, 46000);
    expect(inserted.hppUnitAmount, 20000);
  });

  testWidgets('Tanggal Transaksi defaults to today and is submitted', (tester) async {
    final txRepo = _FakeTransactionRepository();
    await _pumpPage(tester, hppRepo: _FakeHppRepository([_hpp()]), txRepo: txRepo);
    expect(find.text('Tanggal Transaksi'), findsOneWidget);
    await _enter(tester, 'Kode Barang', 'SKU');
    await _enter(tester, 'ID Pesanan', 'ORD');
    await _enter(tester, 'Qty', '1');
    await _enter(tester, 'Harga Jual', '50000');
    await _enter(tester, 'Income', '46000');
    await _selectField<int>(tester, 'HPP', 10);
    await _submit(tester);
    final inserted = txRepo.lastInserted;
    expect(inserted, isNotNull);
    final now = DateTime.now();
    expect(inserted!.transactionDate.year, now.year);
    expect(inserted.transactionDate.month, now.month);
    expect(inserted.transactionDate.day, now.day);
  });

  testWidgets('paid-date button is disabled for pending and enabled for paid', (tester) async {
    await _pumpPage(tester, hppRepo: _FakeHppRepository([_hpp()]), txRepo: _FakeTransactionRepository());
    // Two "PILIH" buttons now exist (transaction date and paid date); the paid
    // date one is rendered last in the ListView.
    final pilihFinder = find.widgetWithText(OutlinedButton, 'PILIH').last;
    expect(pilihFinder, findsOneWidget);
    var button = tester.widget<OutlinedButton>(pilihFinder);
    expect(button.onPressed, isNull);

    await _selectField<PaymentStatus>(tester, 'Status Pembayaran', PaymentStatus.paid);
    button = tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'PILIH').last);
    expect(button.onPressed, isNotNull);
  });

  testWidgets('after successful submit, Harga Jual is cleared and GMV resets to Rp0', (tester) async {
    final txRepo = _FakeTransactionRepository();
    await _pumpPage(tester, hppRepo: _FakeHppRepository([_hpp()]), txRepo: txRepo);
    await _enter(tester, 'Kode Barang', 'SKU');
    await _enter(tester, 'ID Pesanan', 'ORD');
    await _enter(tester, 'Qty', '2');
    await _enter(tester, 'Harga Jual', '50000');
    await _enter(tester, 'Income', '46000');
    await _selectField<int>(tester, 'HPP', 10);
    expect(find.text('Rp100.000'), findsOneWidget);
    await _submit(tester);
    expect(find.text('Rp100.000'), findsNothing);
    final unitPriceField = tester.widget<TextFormField>(find.widgetWithText(TextFormField, 'Harga Jual'));
    expect(unitPriceField.controller?.text, isEmpty);
  });
}