import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiktok_seller/data/models/order.dart';
import 'package:tiktok_seller/data/models/statuses.dart';
import 'package:tiktok_seller/data/models/transaction.dart';
import 'package:tiktok_seller/data/models/transaction_with_order.dart';
import 'package:tiktok_seller/data/repositories/order_repository.dart';
import 'package:tiktok_seller/data/repositories/transaction_repository.dart';
import 'package:tiktok_seller/features/returns/returns_page.dart';

/// Derived from the transitional `Transaction` fixture. Because M7 places the
/// order-level fields (order id, transaction date, payment status, order
/// status, compensation) on `Order`, we materialize a synthetic `Order` from
/// the item's mirror fields for these legacy fixture tests.
Order _derivedOrder(Transaction t) => Order(
      id: t.orderFk,
      accountId: t.accountId ?? 1,
      orderId: t.orderId,
      liveSessionId: t.liveSessionId,
      transactionDate: t.transactionDate,
      paymentStatus: t.paymentStatus,
      orderStatus: t.orderStatus,
      paidAt: t.paidAt,
      returnShippingCompensation: t.returnShippingCompensation,
      paymentDescription: t.paymentDescription,
      createdAt: t.createdAt,
      updatedAt: t.updatedAt,
    );

class _FakeTransactionRepository implements TransactionRepository {
  _FakeTransactionRepository(this._items);
  final List<Transaction> _items;

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
  Future<List<TransactionWithOrder>> listItemsJoined({
    String search = '',
    int? liveSessionId,
    PaymentStatus? paymentStatus,
    OrderStatus? orderStatus,
    DateTime? periodStart,
    DateTime? periodEnd,
  }) async {
    return _items.where((t) {
      if (orderStatus != null && t.orderStatus != orderStatus) return false;
      if (search.isNotEmpty && !t.orderId.contains(search) && !t.productCode.contains(search)) return false;
      if (periodStart != null && t.transactionDate.isBefore(periodStart)) return false;
      if (periodEnd != null && !t.transactionDate.isBefore(periodEnd)) return false;
      return true;
    }).map((t) => TransactionWithOrder(item: t, order: _derivedOrder(t))).toList();
  }

  @override
  Future<void> deleteTransaction(int id) async {}

  @override
  Future<void> updateTransaction(Transaction transaction) async {}

  @override
  Future<void> updateItem(Transaction item) async {}

  @override
  Future<void> deleteItem(int id) async {}
}

class _FakeOrderRepository implements OrderRepository {
  final List<Order> updates = [];

  @override
  Future<int> create(Order order) async => 1;

  @override
  Future<int> createWithItems(Order order, List<Transaction> items) async => 1;

  @override
  Future<Order?> get(int id) async => null;

  @override
  Future<List<Order>> list({int? liveSessionId, DateTime? periodStart, DateTime? periodEnd, String search = ''}) async => const [];

  @override
  Future<void> update(Order order) async {
    updates.add(order);
  }

  @override
  Future<void> delete(int id) async {}
}

Transaction _tx({
  int id = 1,
  int? orderFk,
  String orderId = 'O1',
  String productCode = 'SKU',
  DateTime? date,
  int income = 50000,
  int compensation = 0,
  OrderStatus orderStatus = OrderStatus.returned,
  PaymentStatus paymentStatus = PaymentStatus.paid,
  int qty = 1,
}) {
  final now = DateTime(2026);
  return Transaction(
    id: id,
    orderFk: orderFk ?? id,
    transactionDate: date ?? DateTime(2026, 8, 20),
    productCode: productCode,
    orderId: orderId,
    quantity: qty,
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

Future<_FakeOrderRepository> _pump(WidgetTester tester, List<Transaction> items) async {
  tester.view.physicalSize = const Size(1200, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final repo = _FakeTransactionRepository(items);
  final orders = _FakeOrderRepository();
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: ReturnsPage(transactionRepository: repo, orderRepository: orders)),
  ));
  await tester.pump();
  await tester.pump();
  return orders;
}

Future<void> _search(WidgetTester tester, String query) async {
  await tester.enterText(find.widgetWithText(TextField, 'Cari ID Pesanan'), query);
  await tester.tap(find.text('SEARCH'));
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('shows empty state when there are no returns', (tester) async {
    await _pump(tester, [_tx(orderStatus: OrderStatus.closed)]);
    expect(find.text('Belum ada paket retur periode ini.'), findsOneWidget);
  });

  testWidgets('lists only RETURNED orders', (tester) async {
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

  testWidgets('compensation 0 shows Belum diinput', (tester) async {
    await _pump(tester, [_tx(orderId: 'RET-0', compensation: 0)]);
    expect(find.textContaining('Belum diinput'), findsWidgets);
  });

  testWidgets('search for unknown orderId shows not-found message', (tester) async {
    await _pump(tester, [_tx(orderId: 'RET-1')]);
    await _search(tester, 'NOPE');
    expect(find.text('ID Pesanan tidak ditemukan.'), findsOneWidget);
  });

  testWidgets('search finds an existing RETURNED order and enables the action', (tester) async {
    await _pump(tester, [_tx(id: 7, orderFk: 7, orderId: 'RET-FOUND', orderStatus: OrderStatus.returned)]);
    await _search(tester, 'RET-FOUND');
    expect(find.text('ID Pesanan: RET-FOUND'), findsWidgets);
    final action = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'KOMPENSASI ONGKIR').first,
    );
    expect(action.onPressed, isNotNull);
  });

  testWidgets('search finds RETURNED + cancelled and enables the action', (tester) async {
    await _pump(tester, [
      _tx(id: 8, orderFk: 8, orderId: 'RET-CANC-2', orderStatus: OrderStatus.returned, paymentStatus: PaymentStatus.cancelled),
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

  testWidgets('input compensation via dialog saves the value on the order', (tester) async {
    final orders = await _pump(tester, [_tx(id: 5, orderFk: 5, orderId: 'RET-IN', compensation: 0)]);
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
    expect(orders.updates, hasLength(1));
    expect(orders.updates.single.returnShippingCompensation, 30000);
  });

  testWidgets('edit compensation replaces previous value (not accumulate)', (tester) async {
    final orders = await _pump(tester, [_tx(id: 6, orderFk: 6, orderId: 'RET-EDIT', compensation: 10000)]);
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
    expect(orders.updates, hasLength(1));
    expect(orders.updates.single.returnShippingCompensation, 25000);
  });

  testWidgets('negative incomeAfterReturn is rendered with a minus sign', (tester) async {
    await _pump(tester, [
      _tx(id: 1, orderFk: 1, orderId: 'A', income: 50000, orderStatus: OrderStatus.closed),
      _tx(id: 2, orderFk: 2, orderId: 'B', compensation: 80000),
    ]);
    expect(find.text('Income Setelah Retur: Rp-30.000'), findsOneWidget);
  });
}