import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiktok_seller/data/models/order.dart';
import 'package:tiktok_seller/data/models/statuses.dart';
import 'package:tiktok_seller/data/models/transaction.dart';
import 'package:tiktok_seller/data/models/transaction_with_order.dart';
import 'package:tiktok_seller/data/repositories/order_repository.dart';
import 'package:tiktok_seller/data/repositories/transaction_repository.dart';
import 'package:tiktok_seller/features/returns/returns_page.dart';

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
  }) async => const [];

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
}) {
  final now = DateTime(2026);
  return Transaction(
    id: id,
    orderFk: orderFk ?? id,
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

Future<void> _pump(WidgetTester tester, List<Transaction> items) async {
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

  testWidgets('period filter shows only the selected month', (tester) async {
    await _pump(tester, [
      _tx(id: 1, orderFk: 1, orderId: 'AUG-1', date: DateTime(2026, 8, 5), orderStatus: OrderStatus.returned),
      _tx(id: 2, orderFk: 2, orderId: 'SEP-1', date: DateTime(2026, 9, 5), orderStatus: OrderStatus.returned),
    ]);
    await _selectPeriod(tester, const ReturnPeriod(2026, 9));
    expect(find.text('ID Pesanan: SEP-1'), findsOneWidget);
    expect(find.text('ID Pesanan: AUG-1'), findsNothing);
  });

  testWidgets('search ignores period filter', (tester) async {
    await _pump(tester, [
      _tx(id: 1, orderFk: 1, orderId: 'AUG-RET', date: DateTime(2026, 8, 5), orderStatus: OrderStatus.returned),
      _tx(id: 2, orderFk: 2, orderId: 'SEP-RET', date: DateTime(2026, 9, 5), orderStatus: OrderStatus.returned),
    ]);
    await _selectPeriod(tester, const ReturnPeriod(2026, 8));
    expect(find.text('ID Pesanan: AUG-RET'), findsOneWidget);
    expect(find.text('ID Pesanan: SEP-RET'), findsNothing);
    await _search(tester, 'SEP-RET');
    expect(find.text('ID Pesanan: SEP-RET'), findsWidgets);
  });
}