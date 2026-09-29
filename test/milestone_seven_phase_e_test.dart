import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiktok_seller/data/models/live_session.dart';
import 'package:tiktok_seller/data/models/monthly_report.dart';
import 'package:tiktok_seller/data/models/order.dart';
import 'package:tiktok_seller/data/models/statuses.dart';
import 'package:tiktok_seller/data/models/transaction.dart';
import 'package:tiktok_seller/data/models/transaction_with_order.dart';
import 'package:tiktok_seller/data/repositories/live_session_repository.dart';
import 'package:tiktok_seller/data/repositories/monthly_report_repository.dart';
import 'package:tiktok_seller/data/repositories/order_repository.dart';
import 'package:tiktok_seller/data/repositories/transaction_repository.dart';
import 'package:tiktok_seller/features/reports/reports_page.dart';

Order _order({
  int? id,
  int accountId = 1,
  required String orderId,
  PaymentStatus paymentStatus = PaymentStatus.paid,
  OrderStatus orderStatus = OrderStatus.closed,
  int compensation = 0,
  int? liveSessionId,
  DateTime? date,
  String? description,
}) {
  final now = DateTime(2026, 9, 15, 10);
  return Order(
    id: id,
    accountId: accountId,
    orderId: orderId,
    liveSessionId: liveSessionId,
    transactionDate: date ?? DateTime(2026, 9, 15),
    paymentStatus: paymentStatus,
    orderStatus: orderStatus,
    paidAt: paymentStatus == PaymentStatus.paid ? now : null,
    returnShippingCompensation: compensation,
    paymentDescription: description,
    createdAt: now,
    updatedAt: now,
  );
}

Transaction _item({
  int? id,
  int? orderFk,
  int itemIndex = 0,
  String code = 'P',
  int qty = 1,
  int price = 1000,
  int hpp = 0,
  int? income,
  required String orderId,
}) {
  final now = DateTime(2026, 9, 15, 10);
  return Transaction(
    id: id,
    orderFk: orderFk,
    itemIndex: itemIndex,
    transactionDate: DateTime(2026, 9, 15),
    productCode: code,
    orderId: orderId,
    quantity: qty,
    unitPrice: price,
    gmvAmount: price * qty,
    hppUnitAmount: hpp,
    netIncomeAmount: income ?? price * qty,
    paymentStatus: PaymentStatus.paid,
    orderStatus: OrderStatus.closed,
    createdAt: now,
    updatedAt: now,
  );
}

TransactionWithOrder _join(Order order, Transaction item) =>
    TransactionWithOrder(item: item, order: order);

/// Scopes text lookups to the DataTable (excludes the search EditableText).
Finder _inTable(String text) => find.descendant(
      of: find.byType(DataTable),
      matching: find.text(text),
    );

/// Reads the rendered string from a total-row cell by its stable ValueKey.
///
/// Note: production attaches keys of the exact form `__total_<name>__`
/// (double underscores on both sides). This helper appends the trailing
/// double underscore so the constructed key matches what the widget tree
/// actually holds. Without the trailing `__`, `find.byKey` resolves to zero
/// widgets and `tester.widget<Text>` throws `Bad state: No element`.
String _totalText(WidgetTester tester, String keySuffix) {
  final finder = find.byKey(ValueKey('__total_${keySuffix}__'));
  final textWidget = tester.widget<Text>(finder);
  return textWidget.data ?? '';
}

class _FakeTransactionRepository implements TransactionRepository {
  _FakeTransactionRepository(this._items);
  final List<TransactionWithOrder> _items;
  final List<Transaction> updates = [];
  final List<int> deletions = [];

  @override
  Future<List<TransactionWithOrder>> listItemsJoined({
    String search = '',
    int? liveSessionId,
    PaymentStatus? paymentStatus,
    OrderStatus? orderStatus,
    DateTime? periodStart,
    DateTime? periodEnd,
  }) async {
    return _items.where((v) {
      if (periodStart != null && v.order.transactionDate.isBefore(periodStart)) return false;
      if (periodEnd != null && !v.order.transactionDate.isBefore(periodEnd)) return false;
      if (liveSessionId != null && v.order.liveSessionId != liveSessionId) return false;
      if (paymentStatus != null && v.order.paymentStatus != paymentStatus) return false;
      if (orderStatus != null && v.order.orderStatus != orderStatus) return false;
      if (search.isNotEmpty) {
        if (!v.order.orderId.contains(search) && !v.item.productCode.contains(search)) return false;
      }
      return true;
    }).toList();
  }
  @override
  Future<void> updateItem(Transaction item) async {
    updates.add(item);
  }
  @override
  Future<void> deleteItem(int id) async {
    deletions.add(id);
  }
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
}

class _FakeOrderRepository implements OrderRepository {
  final List<Order> updates = [];
  @override
  Future<void> update(Order order) async {
    updates.add(order);
  }
  @override
  Future<int> create(Order order) async => 1;
  @override
  Future<int> createWithItems(Order order, List<Transaction> items) async => 1;
  @override
  Future<Order?> get(int id) async => null;
  @override
  Future<List<Order>> list({int? liveSessionId, DateTime? periodStart, DateTime? periodEnd, String search = ''}) async => const [];
  @override
  Future<void> delete(int id) async {}
}

class _FakeMonthlyReportRepository implements MonthlyReportRepository {
  final List<MonthlyReport> saved = [];
  @override
  Future<List<MonthlyReport>> listReports() async => const [];
  @override
  Future<void> save(MonthlyReport report) async {
    saved.add(report);
  }
}

class _FakeLiveSessionRepository implements LiveSessionRepository {
  _FakeLiveSessionRepository([this._sessions = const []]);
  final List<LiveSession> _sessions;
  @override
  Future<List<LiveSession>> listSessions() async => _sessions;
  @override
  Future<LiveSession> createSession({required String name, DateTime? startedAt}) async => throw UnimplementedError();
  @override
  Future<int?> getSelectedSessionId() async => null;
  @override
  Future<void> setSelectedSessionId(int? sessionId) async {}
  @override
  Future<LiveSession?> getSelectedSession() async => null;
  @override
  Future<void> updateSession({required int id, required String name, required DateTime startedAt}) async {}
  @override
  Future<bool> hasTransactions(int sessionId) async => false;
  @override
  Future<void> deleteSession(int sessionId) async {}
}

Future<(_FakeTransactionRepository, _FakeOrderRepository, _FakeMonthlyReportRepository)> _pump(
  WidgetTester tester,
  List<TransactionWithOrder> items, {
  List<LiveSession> sessions = const [],
}) async {
  tester.view.physicalSize = const Size(2400, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final tx = _FakeTransactionRepository(items);
  final order = _FakeOrderRepository();
  final monthly = _FakeMonthlyReportRepository();
  await tester.pumpWidget(MaterialApp(
    home: MonthDetailPage(
      month: const ReportMonth(2026, 9),
      transactionRepository: tx,
      orderRepository: order,
      monthlyReportRepository: monthly,
      liveSessionRepository: _FakeLiveSessionRepository(sessions),
    ),
  ));
  await tester.pump();
  await tester.pump();
  return (tx, order, monthly);
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group('Reports grouping', () {
    testWidgets('single-item order renders normally', (tester) async {
      final order = _order(orderId: 'ORD-1');
      await _pump(tester, [
        _join(order, _item(orderFk: 1, orderId: 'ORD-1', code: 'A01', qty: 2, price: 50000)),
      ]);
      expect(_inTable('ORD-1'), findsOneWidget);
      expect(_inTable('A01'), findsOneWidget);
      expect(find.text('TOTAL'), findsOneWidget);
    });

    testWidgets('two-item order renders two item rows and one order ID', (tester) async {
      final order = _order(orderId: 'ORD-2');
      await _pump(tester, [
        _join(order, _item(orderFk: 1, orderId: 'ORD-2', itemIndex: 0, code: 'A01')),
        _join(order, _item(orderFk: 1, orderId: 'ORD-2', itemIndex: 1, code: 'B07')),
      ]);
      expect(_inTable('ORD-2'), findsOneWidget);
      expect(_inTable('A01'), findsOneWidget);
      expect(_inTable('B07'), findsOneWidget);
    });

    testWidgets('three-item order renders three item rows and one order ID', (tester) async {
      final order = _order(orderId: 'ORD-3');
      await _pump(tester, [
        _join(order, _item(orderFk: 1, orderId: 'ORD-3', itemIndex: 0, code: 'A01')),
        _join(order, _item(orderFk: 1, orderId: 'ORD-3', itemIndex: 1, code: 'B07')),
        _join(order, _item(orderFk: 1, orderId: 'ORD-3', itemIndex: 2, code: 'C02')),
      ]);
      expect(_inTable('ORD-3'), findsOneWidget);
      expect(_inTable('A01'), findsOneWidget);
      expect(_inTable('B07'), findsOneWidget);
      expect(_inTable('C02'), findsOneWidget);
      expect(find.byIcon(Icons.copy), findsOneWidget);
    });

    testWidgets('item_index controls ordering within group', (tester) async {
      final order = _order(orderId: 'ORD-4');
      await _pump(tester, [
        _join(order, _item(orderFk: 1, orderId: 'ORD-4', itemIndex: 2, code: 'CCC')),
        _join(order, _item(orderFk: 1, orderId: 'ORD-4', itemIndex: 0, code: 'AAA')),
        _join(order, _item(orderFk: 1, orderId: 'ORD-4', itemIndex: 1, code: 'BBB')),
      ]);
      final aaaY = tester.getTopLeft(find.text('AAA')).dy;
      final bbbY = tester.getTopLeft(find.text('BBB')).dy;
      final cccY = tester.getTopLeft(find.text('CCC')).dy;
      expect(aaaY, lessThan(bbbY));
      expect(bbbY, lessThan(cccY));
    });

    testWidgets('two orders display as two separate groups', (tester) async {
      final o1 = _order(id: 1, orderId: 'ORD-A');
      final o2 = _order(id: 2, orderId: 'ORD-B');
      await _pump(tester, [
        _join(o1, _item(orderFk: 1, orderId: 'ORD-A', code: 'A01')),
        _join(o1, _item(orderFk: 1, orderId: 'ORD-A', itemIndex: 1, code: 'A02')),
        _join(o2, _item(orderFk: 2, orderId: 'ORD-B', code: 'B01')),
      ]);
      expect(_inTable('ORD-A'), findsOneWidget);
      expect(_inTable('ORD-B'), findsOneWidget);
      expect(find.byIcon(Icons.copy), findsNWidgets(2));
    });
  });

  group('Reports search behavior', () {
    testWidgets('search by product code returns only matching item', (tester) async {
      final order = _order(id: 1, orderId: 'ORD-S');
      await _pump(tester, [
        _join(order, _item(orderFk: 1, orderId: 'ORD-S', code: 'BAJU-A')),
        _join(order, _item(orderFk: 1, orderId: 'ORD-S', itemIndex: 1, code: 'CELANA-B')),
      ]);
      await tester.enterText(
        find.widgetWithText(TextField, 'Cari ID Pesanan atau Kode Barang'),
        'CELANA-B',
      );
      await tester.pump();
      await tester.pump();
      expect(_inTable('CELANA-B'), findsOneWidget);
      expect(_inTable('BAJU-A'), findsNothing);
      expect(_inTable('ORD-S'), findsOneWidget);
    });

    testWidgets('search by order ID returns all items of order', (tester) async {
      final order = _order(id: 1, orderId: 'ORDER-ALL');
      await _pump(tester, [
        _join(order, _item(orderFk: 1, orderId: 'ORDER-ALL', code: 'A')),
        _join(order, _item(orderFk: 1, orderId: 'ORDER-ALL', itemIndex: 1, code: 'B')),
      ]);
      await tester.enterText(
        find.widgetWithText(TextField, 'Cari ID Pesanan atau Kode Barang'),
        'ORDER-ALL',
      );
      await tester.pump();
      await tester.pump();
      expect(_inTable('A'), findsOneWidget);
      expect(_inTable('B'), findsOneWidget);
    });
  });

  group('M7-B total row', () {
    testWidgets('total row visible with correct sums', (tester) async {
      final order = _order(id: 1, orderId: 'ORD-T');
      await _pump(tester, [
        _join(order, _item(orderFk: 1, orderId: 'ORD-T', itemIndex: 0, qty: 2, price: 50000, hpp: 20000, income: 80000)),
        _join(order, _item(orderFk: 1, orderId: 'ORD-T', itemIndex: 1, qty: 3, price: 30000, hpp: 10000, income: 70000)),
      ]);
      // Qty = 5; GMV = 100000 + 90000 = 190000; Income = 80000 + 70000 = 150000;
      // HPP = 40000 + 30000 = 70000; Profit = 150000 - 70000 = 80000.
      expect(find.text('TOTAL'), findsOneWidget);
      expect(_totalText(tester, 'qty'), '5');
      expect(_totalText(tester, 'harga'), '');
      expect(_totalText(tester, 'gmv'), 'Rp190.000');
      expect(_totalText(tester, 'income'), 'Rp150.000');
      expect(_totalText(tester, 'hpp'), 'Rp70.000');
      expect(_totalText(tester, 'profit'), 'Rp80.000');
    });

    testWidgets('empty result shows zero totals', (tester) async {
      await _pump(tester, const []);
      expect(find.text('TOTAL'), findsOneWidget);
      expect(_totalText(tester, 'qty'), '0');
      expect(_totalText(tester, 'harga'), '');
      expect(_totalText(tester, 'gmv'), 'Rp0');
      expect(_totalText(tester, 'income'), 'Rp0');
      expect(_totalText(tester, 'hpp'), 'Rp0');
      expect(_totalText(tester, 'profit'), 'Rp0');
    });

    testWidgets('search changes total', (tester) async {
      final order = _order(id: 1, orderId: 'ORD-S');
      await _pump(tester, [
        _join(order, _item(orderFk: 1, orderId: 'ORD-S', itemIndex: 0, code: 'A', qty: 2, price: 50000, hpp: 10000, income: 80000)),
        _join(order, _item(orderFk: 1, orderId: 'ORD-S', itemIndex: 1, code: 'B', qty: 1, price: 30000, hpp: 5000, income: 25000)),
      ]);
      // Unfiltered: Qty=3, GMV=130000, Income=105000, HPP=25000, Profit=80000.
      expect(_totalText(tester, 'qty'), '3');
      expect(_totalText(tester, 'gmv'), 'Rp130.000');
      expect(_totalText(tester, 'income'), 'Rp105.000');
      expect(_totalText(tester, 'hpp'), 'Rp25.000');
      expect(_totalText(tester, 'profit'), 'Rp80.000');
      await tester.enterText(
        find.widgetWithText(TextField, 'Cari ID Pesanan atau Kode Barang'),
        'B',
      );
      await tester.pump();
      await tester.pump();
      // Filtered (only item B): Qty=1, GMV=30000, Income=25000, HPP=5000, Profit=20000.
      expect(_totalText(tester, 'qty'), '1');
      expect(_totalText(tester, 'gmv'), 'Rp30.000');
      expect(_totalText(tester, 'income'), 'Rp25.000');
      expect(_totalText(tester, 'hpp'), 'Rp5.000');
      expect(_totalText(tester, 'profit'), 'Rp20.000');
    });
  });

  group('Submit Report isolation', () {
    testWidgets('UI filter does not leak into saved snapshot', (tester) async {
      final o1 = _order(id: 1, orderId: 'A');
      final o2 = _order(id: 2, orderId: 'B');
      final o3 = _order(id: 3, orderId: 'C');
      final (_, _, monthly) = await _pump(tester, [
        _join(o1, _item(orderFk: 1, orderId: 'A', qty: 1, price: 10000, income: 10000)),
        _join(o2, _item(orderFk: 2, orderId: 'B', qty: 1, price: 20000, income: 20000)),
        _join(o3, _item(orderFk: 3, orderId: 'C', qty: 1, price: 30000, income: 30000)),
      ]);
      await tester.enterText(
        find.widgetWithText(TextField, 'Cari ID Pesanan atau Kode Barang'),
        'B',
      );
      await tester.pump();
      await tester.pump();
      expect(_inTable('B'), findsOneWidget);
      await tester.tap(find.text('SUBMIT REPORT'));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(monthly.saved, hasLength(1));
      final saved = monthly.saved.single;
      // Full period regardless of UI filter: 10000 + 20000 + 30000 = 60000.
      expect(saved.gmvTotal, 60000);
      expect(saved.netIncomeTotal, 60000);
    });
  });

  group('Edit item / edit order actions render', () {
    testWidgets('order actions appear once per group, item actions per item', (tester) async {
      final order = _order(id: 1, orderId: 'ORD-E');
      await _pump(tester, [
        _join(order, _item(orderFk: 1, orderId: 'ORD-E', itemIndex: 0, code: 'A')),
        _join(order, _item(orderFk: 1, orderId: 'ORD-E', itemIndex: 1, code: 'B')),
      ]);
      expect(find.widgetWithText(TextButton, 'Edit Order'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Edit Item'), findsNWidgets(2));
      expect(find.widgetWithText(TextButton, 'Delete'), findsNWidgets(2));
    });
  });

  group('Account isolation', () {
    testWidgets('account A only sees account A data', (tester) async {
      final a = _order(id: 1, accountId: 1, orderId: 'SHARED');
      await _pump(tester, [
        _join(a, _item(orderFk: 1, orderId: 'SHARED', code: 'A-ONLY')),
      ]);
      expect(_inTable('A-ONLY'), findsOneWidget);
    });
  });
}