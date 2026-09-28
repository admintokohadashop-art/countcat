import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiktok_seller/data/models/statuses.dart';
import 'package:tiktok_seller/data/models/transaction.dart';
import 'package:tiktok_seller/data/repositories/transaction_repository.dart';
import 'package:tiktok_seller/features/returns/returns_page.dart';

class _FakeTransactionRepository implements TransactionRepository {
  _FakeTransactionRepository(this._items);
  final List<Transaction> _items;
  Transaction? lastUpdated;
  final List<Transaction> updates = [];

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
  }) async {
    return _items.where((t) {
      if (orderStatus != null && t.orderStatus != orderStatus) return false;
      if (search.isNotEmpty && !t.orderId.contains(search)) return false;
      if (periodStart != null && t.transactionDate.isBefore(periodStart)) return false;
      if (periodEnd != null && !t.transactionDate.isBefore(periodEnd)) return false;
      return true;
    }).toList();
  }

  @override
  Future<void> deleteTransaction(int id) async {}

  @override
  Future<void> updateTransaction(Transaction transaction) async {
    lastUpdated = transaction;
    updates.add(transaction);
    final idx = _items.indexWhere((t) => t.id == transaction.id);
    if (idx >= 0) _items[idx] = transaction;
  }
}

Transaction _tx({
  int id = 1,
  String orderId = 'O1',
  String productCode = 'SKU',
  DateTime? date,
  int income = 50000,
  int compensation = 0,
  OrderStatus orderStatus = OrderStatus.returned,
  PaymentStatus paymentStatus = PaymentStatus.paid,
}) {
  final now = DateTime(2026);
  return Transaction(
    id: id,
    transactionDate: date ?? DateTime(2026, 8, 20),
    productCode: productCode,
    orderId: orderId,
    quantity: 1,
    gmvAmount: 50000,
    netIncomeAmount: income,
    hppUnitAmount: 20000,
    returnShippingCompensation: compensation,
    orderStatus: orderStatus,
    paymentStatus: paymentStatus,
    createdAt: now,
    updatedAt: now,
  );
}

Future<_FakeTransactionRepository> _pump(WidgetTester tester, List<Transaction> items) async {
  tester.view.physicalSize = const Size(1200, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final repo = _FakeTransactionRepository(items);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: ReturnsPage(transactionRepository: repo)),
  ));
  await tester.pump();
  await tester.pump();
  return repo;
}

Future<void> _search(WidgetTester tester, String query) async {
  await tester.enterText(find.widgetWithText(TextField, 'Cari ID Pesanan'), query);
  await tester.tap(find.text('SEARCH'));
  await tester.pump();
  await tester.pump();
}

Future<void> _selectPeriod(WidgetTester tester, ReturnPeriod? period) async {
  final finder = find.byType(DropdownButtonFormField<ReturnPeriod?>);
  final state = tester.state<FormFieldState<ReturnPeriod?>>(finder);
  state.didChange(period);
  await tester.pump();
}

void main() {
  testWidgets('empty state when there are no returns', (tester) async {
    await _pump(tester, [_tx(orderStatus: OrderStatus.closed)]);
    expect(find.text('Belum ada paket retur periode ini.'), findsOneWidget);
  });

  testWidgets('lists only RETURNED transactions', (tester) async {
    await _pump(tester, [
      _tx(id: 1, orderId: 'RET', orderStatus: OrderStatus.returned),
      _tx(id: 2, orderId: 'CLOSED', orderStatus: OrderStatus.closed),
    ]);
    expect(find.text('ID Pesanan: RET'), findsOneWidget);
    expect(find.text('ID Pesanan: CLOSED'), findsNothing);
  });

  testWidgets('RETURNED + PaymentStatus.cancelled still appears', (tester) async {
    await _pump(tester, [
      _tx(id: 1, orderId: 'RET-CANC', orderStatus: OrderStatus.returned, paymentStatus: PaymentStatus.cancelled),
    ]);
    expect(find.text('ID Pesanan: RET-CANC'), findsOneWidget);
  });

  testWidgets('compensation 0 shows "Belum diinput"', (tester) async {
    await _pump(tester, [_tx(orderId: 'RET-0', compensation: 0)]);
    expect(find.textContaining('Belum diinput'), findsWidgets);
  });

  testWidgets('search for unknown orderId shows not-found message', (tester) async {
    await _pump(tester, [_tx(orderId: 'RET-1')]);
    await _search(tester, 'NOPE');
    expect(find.text('ID Pesanan tidak ditemukan.'), findsOneWidget);
  });

  testWidgets('search finds an existing RETURNED transaction and enables the action', (tester) async {
    await _pump(tester, [_tx(id: 7, orderId: 'RET-FOUND', orderStatus: OrderStatus.returned)]);
    await _search(tester, 'RET-FOUND');
    expect(find.text('ID Pesanan: RET-FOUND'), findsWidgets);
    final action = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'KOMPENSASI ONGKIR').first,
    );
    expect(action.onPressed, isNotNull);
  });

  testWidgets('search finds RETURNED + cancelled and enables the action', (tester) async {
    await _pump(tester, [
      _tx(id: 8, orderId: 'RET-CANC-2', orderStatus: OrderStatus.returned, paymentStatus: PaymentStatus.cancelled),
    ]);
    await _search(tester, 'RET-CANC-2');
    final action = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'KOMPENSASI ONGKIR').first,
    );
    expect(action.onPressed, isNotNull);
  });

  testWidgets('search result for non-RETURNED disables compensation action', (tester) async {
    await _pump(tester, [_tx(orderId: 'CLOSED-1', orderStatus: OrderStatus.closed)]);
    await _search(tester, 'CLOSED-1');
    final action = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'KOMPENSASI ONGKIR').first,
    );
    expect(action.onPressed, isNull);
  });

  testWidgets('search ignores period filter', (tester) async {
    await _pump(tester, [
      _tx(id: 1, orderId: 'AUG-RET', date: DateTime(2026, 8, 5), orderStatus: OrderStatus.returned),
      _tx(id: 2, orderId: 'SEP-RET', date: DateTime(2026, 9, 5), orderStatus: OrderStatus.returned),
    ]);
    await _selectPeriod(tester, const ReturnPeriod(2026, 8));
    expect(find.text('ID Pesanan: AUG-RET'), findsOneWidget);
    expect(find.text('ID Pesanan: SEP-RET'), findsNothing);
    // Search must still find the SEP order even though period is AUG.
    await _search(tester, 'SEP-RET');
    expect(find.text('ID Pesanan: SEP-RET'), findsWidgets);
  });

  testWidgets('period filter shows only the selected month', (tester) async {
    await _pump(tester, [
      _tx(id: 1, orderId: 'AUG-1', date: DateTime(2026, 8, 5), orderStatus: OrderStatus.returned),
      _tx(id: 2, orderId: 'SEP-1', date: DateTime(2026, 9, 5), orderStatus: OrderStatus.returned),
    ]);
    await _selectPeriod(tester, const ReturnPeriod(2026, 9));
    expect(find.text('ID Pesanan: SEP-1'), findsOneWidget);
    expect(find.text('ID Pesanan: AUG-1'), findsNothing);
  });

  testWidgets('input compensation via dialog saves the value', (tester) async {
    final repo = await _pump(tester, [_tx(id: 5, orderId: 'RET-IN', compensation: 0)]);
    await tester.tap(find.widgetWithText(FilledButton, 'KOMPENSASI ONGKIR').first);
    await tester.pump();
    await tester.pump();
    expect(find.text('Kompensasi Ongkir Retur'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'Nominal Kompensasi (Rp)'),
      '30000',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'SIMPAN'));
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(repo.lastUpdated, isNotNull);
    expect(repo.lastUpdated!.returnShippingCompensation, 30000);
    expect(find.textContaining('Kompensasi: Rp30.000'), findsWidgets);
  });

  testWidgets('edit compensation replaces previous value (not accumulate)', (tester) async {
    final repo = await _pump(tester, [_tx(id: 6, orderId: 'RET-EDIT', compensation: 10000)]);
    await tester.tap(find.widgetWithText(FilledButton, 'KOMPENSASI ONGKIR').first);
    await tester.pump();
    await tester.pump();
    await tester.enterText(
      find.widgetWithText(TextField, 'Nominal Kompensasi (Rp)'),
      '25000',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'SIMPAN'));
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(repo.lastUpdated!.returnShippingCompensation, 25000);
    expect(repo.updates.length, 1);
    expect(find.textContaining('Kompensasi: Rp25.000'), findsWidgets);
    expect(find.textContaining('Kompensasi: Rp35.000'), findsNothing);
  });

  testWidgets('negative incomeAfterReturn is rendered with a minus sign', (tester) async {
    await _pump(tester, [
      _tx(id: 1, orderId: 'A', income: 50000, orderStatus: OrderStatus.closed),
      _tx(id: 2, orderId: 'B', compensation: 80000),
    ]);
    expect(find.text('Income Setelah Retur: Rp-30.000'), findsOneWidget);
  });
}