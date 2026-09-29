import 'package:flutter_test/flutter_test.dart';
import 'package:tiktok_seller/data/models/order.dart';
import 'package:tiktok_seller/data/models/statuses.dart';
import 'package:tiktok_seller/data/models/transaction.dart';
import 'package:tiktok_seller/data/models/transaction_with_order.dart';
import 'package:tiktok_seller/features/dashboard/dashboard_totals.dart';
import 'package:tiktok_seller/features/reports/report_totals.dart';
import 'package:tiktok_seller/features/returns/return_totals.dart';

Order _order({
  int? id,
  int accountId = 1,
  required String orderId,
  PaymentStatus paymentStatus = PaymentStatus.paid,
  OrderStatus orderStatus = OrderStatus.closed,
  int returnShippingCompensation = 0,
}) {
  final now = DateTime(2026, 9, 15, 10);
  return Order(
    id: id,
    accountId: accountId,
    orderId: orderId,
    transactionDate: DateTime(2026, 9, 15),
    paymentStatus: paymentStatus,
    orderStatus: orderStatus,
    paidAt: paymentStatus == PaymentStatus.paid ? now : null,
    returnShippingCompensation: returnShippingCompensation,
    createdAt: now,
    updatedAt: now,
  );
}

Transaction _item({
  int? id,
  int? orderFk,
  int quantity = 1,
  int unitPrice = 1000,
  int hppUnitAmount = 0,
  int? netIncomeAmount,
  String productCode = 'P',
  required String orderId,
}) {
  final now = DateTime(2026, 9, 15, 10);
  return Transaction(
    id: id,
    orderFk: orderFk,
    transactionDate: DateTime(2026, 9, 15),
    productCode: productCode,
    orderId: orderId,
    quantity: quantity,
    unitPrice: unitPrice,
    gmvAmount: unitPrice * quantity,
    hppUnitAmount: hppUnitAmount,
    netIncomeAmount: netIncomeAmount ?? unitPrice * quantity,
    paymentStatus: PaymentStatus.paid,
    orderStatus: OrderStatus.closed,
    createdAt: now,
    updatedAt: now,
  );
}

TransactionWithOrder _join(Order order, Transaction item) =>
    TransactionWithOrder(item: item, order: order);

void main() {
  group('ReportTotals — M7 multi-item', () {
    test('single-item order regression (unchanged totals)', () {
      final t = ReportTotals.fromJoined([
        _join(_order(orderId: 'O1'), _item(orderId: 'O1', unitPrice: 50000, quantity: 2, hppUnitAmount: 20000, netIncomeAmount: 90000)),
      ]);
      expect(t.gmv, 100000);
      expect(t.netIncome, 90000);
      expect(t.hpp, 40000);
      expect(t.profit, 50000);
    });

    test('two items in one active order: sums per item', () {
      final order = _order(orderId: 'O1');
      final t = ReportTotals.fromJoined([
        _join(order, _item(orderId: 'O1', unitPrice: 20000, quantity: 1, hppUnitAmount: 5000, netIncomeAmount: 16000)),
        _join(order, _item(orderId: 'O1', unitPrice: 30000, quantity: 2, hppUnitAmount: 10000, netIncomeAmount: 50000)),
      ]);
      expect(t.gmv, 20000 + 60000);
      expect(t.netIncome, 16000 + 50000);
      expect(t.hpp, 5000 + 20000);
      expect(t.profit, 66000 - 25000);
    });

    test('three items with different prices/qty/hpp/income', () {
      final order = _order(orderId: 'O1');
      final t = ReportTotals.fromJoined([
        _join(order, _item(orderId: 'O1', unitPrice: 21000, quantity: 1, hppUnitAmount: 8000, netIncomeAmount: 15000)),
        _join(order, _item(orderId: 'O1', unitPrice: 27000, quantity: 1, hppUnitAmount: 10000, netIncomeAmount: 20000)),
        _join(order, _item(orderId: 'O1', unitPrice: 30000, quantity: 2, hppUnitAmount: 12000, netIncomeAmount: 50000)),
      ]);
      expect(t.gmv, 21000 + 27000 + 60000);
      expect(t.netIncome, 15000 + 20000 + 50000);
      expect(t.hpp, 8000 + 10000 + 24000);
      expect(t.profit, 85000 - 42000);
    });

    test('returned order: GMV included but income/HPP excluded', () {
      final returnedOrder = _order(orderId: 'RET', orderStatus: OrderStatus.returned);
      final t = ReportTotals.fromJoined([
        _join(returnedOrder, _item(orderId: 'RET', unitPrice: 50000, quantity: 2, hppUnitAmount: 20000, netIncomeAmount: 90000)),
      ]);
      expect(t.gmv, 100000);
      expect(t.netIncome, 0);
      expect(t.hpp, 0);
      expect(t.profit, 0);
    });

    test('cancelled-payment order: GMV included but income/HPP excluded', () {
      final cancelled = _order(orderId: 'C', paymentStatus: PaymentStatus.cancelled);
      final t = ReportTotals.fromJoined([
        _join(cancelled, _item(orderId: 'C', unitPrice: 30000, quantity: 2, hppUnitAmount: 15000, netIncomeAmount: 50000)),
      ]);
      expect(t.gmv, 60000);
      expect(t.netIncome, 0);
      expect(t.hpp, 0);
    });

    test('cancel order: GMV included but income/HPP excluded', () {
      final cancel = _order(orderId: 'X', orderStatus: OrderStatus.cancel);
      final t = ReportTotals.fromJoined([
        _join(cancel, _item(orderId: 'X', unitPrice: 25000, quantity: 4, hppUnitAmount: 10000, netIncomeAmount: 80000)),
      ]);
      expect(t.gmv, 100000);
      expect(t.netIncome, 0);
      expect(t.hpp, 0);
    });

    test('mixed: active + returned + cancelled + cancel orders', () {
      final active = _order(orderId: 'A');
      final returned = _order(orderId: 'R', orderStatus: OrderStatus.returned);
      final cancelled = _order(orderId: 'P', paymentStatus: PaymentStatus.cancelled);
      final cancel = _order(orderId: 'X', orderStatus: OrderStatus.cancel);
      final t = ReportTotals.fromJoined([
        _join(active, _item(orderId: 'A', unitPrice: 20000, quantity: 2, hppUnitAmount: 5000, netIncomeAmount: 30000)),
        _join(returned, _item(orderId: 'R', unitPrice: 10000, quantity: 1, hppUnitAmount: 3000, netIncomeAmount: 8000)),
        _join(cancelled, _item(orderId: 'P', unitPrice: 5000, quantity: 1, hppUnitAmount: 1000, netIncomeAmount: 4000)),
        _join(cancel, _item(orderId: 'X', unitPrice: 7000, quantity: 3, hppUnitAmount: 2000, netIncomeAmount: 6000)),
      ]);
      expect(t.gmv, 40000 + 10000 + 5000 + 21000);
      expect(t.netIncome, 30000);
      expect(t.hpp, 10000);
      expect(t.profit, 20000);
    });
  });

  group('ReturnTotals — M7 multi-item', () {
    test('one returned order with one item', () {
      final r = ReturnTotals.fromJoined([
        _join(
          _order(orderId: 'R', orderStatus: OrderStatus.returned, returnShippingCompensation: 30000),
          _item(orderId: 'R', unitPrice: 50000, quantity: 1, hppUnitAmount: 20000, netIncomeAmount: 40000),
        ),
      ]);
      expect(r.returnedCount, 1);
      expect(r.returnedQty, 1);
      expect(r.totalCompensation, 30000);
    });

    test('one returned order with multiple items: compensation counted once', () {
      final returned = _order(orderId: 'R', orderStatus: OrderStatus.returned, returnShippingCompensation: 10000);
      final r = ReturnTotals.fromJoined([
        _join(returned, _item(orderId: 'R', quantity: 2)),
        _join(returned, _item(orderId: 'R', quantity: 3)),
        _join(returned, _item(orderId: 'R', quantity: 1)),
      ]);
      expect(r.returnedCount, 1);
      expect(r.returnedQty, 6);
      expect(r.totalCompensation, 10000);
    });

    test('multiple returned orders: compensation sums once per order', () {
      final r1 = _order(id: 1, orderId: 'R1', orderStatus: OrderStatus.returned, returnShippingCompensation: 10000);
      final r2 = _order(id: 2, orderId: 'R2', orderStatus: OrderStatus.returned, returnShippingCompensation: 25000);
      final r = ReturnTotals.fromJoined([
        _join(r1, _item(orderId: 'R1', quantity: 2)),
        _join(r1, _item(orderId: 'R1', quantity: 1)),
        _join(r2, _item(orderId: 'R2', quantity: 4)),
      ]);
      expect(r.returnedCount, 2);
      expect(r.returnedQty, 7);
      expect(r.totalCompensation, 35000);
    });

    test('zero compensation works', () {
      final r = ReturnTotals.fromJoined([
        _join(_order(orderId: 'R', orderStatus: OrderStatus.returned, returnShippingCompensation: 0), _item(orderId: 'R')),
      ]);
      expect(r.totalCompensation, 0);
      expect(r.returnedQty, 1);
    });

    test('active income/HPP exclude returned orders', () {
      final active = _order(orderId: 'A');
      final returned = _order(orderId: 'R', orderStatus: OrderStatus.returned, returnShippingCompensation: 30000);
      final r = ReturnTotals.fromJoined([
        _join(active, _item(orderId: 'A', unitPrice: 50000, quantity: 2, hppUnitAmount: 20000, netIncomeAmount: 90000)),
        _join(returned, _item(orderId: 'R', unitPrice: 10000, quantity: 3, hppUnitAmount: 1000, netIncomeAmount: 5000)),
      ]);
      expect(r.activeIncome, 90000);
      expect(r.activeHpp, 40000);
      expect(r.totalCompensation, 30000);
      expect(r.incomeAfterReturn, 60000);
      expect(r.profitAfterReturn, 20000);
    });

    test('RETURNED + payment cancelled: still counts as returned', () {
      final order = _order(
        orderId: 'R',
        paymentStatus: PaymentStatus.cancelled,
        orderStatus: OrderStatus.returned,
        returnShippingCompensation: 25000,
      );
      final r = ReturnTotals.fromJoined([
        _join(order, _item(orderId: 'R', quantity: 3)),
      ]);
      expect(r.returnedCount, 1);
      expect(r.returnedQty, 3);
      expect(r.totalCompensation, 25000);
      expect(r.activeIncome, 0);
      expect(r.activeHpp, 0);
    });

    test('negative incomeAfterReturn and profitAfterReturn are not clamped', () {
      final active = _order(orderId: 'A');
      final returned = _order(orderId: 'R', orderStatus: OrderStatus.returned, returnShippingCompensation: 80000);
      final r = ReturnTotals.fromJoined([
        _join(active, _item(orderId: 'A', unitPrice: 50000, quantity: 1, hppUnitAmount: 20000, netIncomeAmount: 50000)),
        _join(returned, _item(orderId: 'R', quantity: 1)),
      ]);
      expect(r.incomeAfterReturn, -30000);
      expect(r.profitAfterReturn, -50000);
    });
  });

  group('DashboardTotals — M7 multi-item', () {
    test('single-item regression (unchanged totals)', () {
      final t = DashboardTotals.fromJoined([
        _join(_order(orderId: 'O1'), _item(orderId: 'O1', unitPrice: 50000, quantity: 3, hppUnitAmount: 20000, netIncomeAmount: 140000)),
      ]);
      expect(t.itemsSold, 3);
      expect(t.gmv, 150000);
      expect(t.activeIncome, 140000);
      expect(t.activeHpp, 60000);
      expect(t.profit, 80000);
      expect(t.returnedQty, 0);
      expect(t.totalCompensation, 0);
    });

    test('multi-item active quantities and totals', () {
      final active = _order(orderId: 'A');
      final t = DashboardTotals.fromJoined([
        _join(active, _item(orderId: 'A', unitPrice: 50000, quantity: 2, hppUnitAmount: 20000, netIncomeAmount: 80000)),
        _join(active, _item(orderId: 'A', unitPrice: 30000, quantity: 4, hppUnitAmount: 10000, netIncomeAmount: 100000)),
      ]);
      expect(t.itemsSold, 6);
      expect(t.gmv, 100000 + 120000);
      expect(t.activeIncome, 180000);
      expect(t.activeHpp, 40000 + 40000);
      expect(t.profit, 100000);
    });

    test('multi-item returned order: qty summed, compensation once', () {
      final returned = _order(orderId: 'R', orderStatus: OrderStatus.returned, returnShippingCompensation: 15000);
      final t = DashboardTotals.fromJoined([
        _join(returned, _item(orderId: 'R', quantity: 3)),
        _join(returned, _item(orderId: 'R', quantity: 1)),
      ]);
      expect(t.returnedQty, 4);
      expect(t.totalCompensation, 15000);
      expect(t.itemsSold, 0);
    });

    test('active + returned orders together', () {
      final active = _order(orderId: 'A');
      final returned = _order(orderId: 'R', orderStatus: OrderStatus.returned, returnShippingCompensation: 15000);
      final t = DashboardTotals.fromJoined([
        _join(active, _item(orderId: 'A', unitPrice: 10000, quantity: 2, hppUnitAmount: 3000, netIncomeAmount: 16000)),
        _join(active, _item(orderId: 'A', unitPrice: 20000, quantity: 4, hppUnitAmount: 5000, netIncomeAmount: 70000)),
        _join(returned, _item(orderId: 'R', unitPrice: 5000, quantity: 3, hppUnitAmount: 1000, netIncomeAmount: 4000)),
        _join(returned, _item(orderId: 'R', unitPrice: 5000, quantity: 1, hppUnitAmount: 1000, netIncomeAmount: 2000)),
      ]);
      expect(t.itemsSold, 6);
      expect(t.returnedQty, 4);
      expect(t.totalCompensation, 15000);
      expect(t.activeIncome, 16000 + 70000);
      expect(t.activeHpp, 6000 + 20000);
      expect(t.profit, 86000 - 26000);
    });

    test('cancelled payment + cancel orders excluded from active', () {
      final cancelled = _order(orderId: 'P', paymentStatus: PaymentStatus.cancelled);
      final cancel = _order(orderId: 'X', orderStatus: OrderStatus.cancel);
      final t = DashboardTotals.fromJoined([
        _join(cancelled, _item(orderId: 'P', unitPrice: 10000, quantity: 2, netIncomeAmount: 15000)),
        _join(cancel, _item(orderId: 'X', unitPrice: 20000, quantity: 1, netIncomeAmount: 18000)),
      ]);
      expect(t.itemsSold, 0);
      expect(t.activeIncome, 0);
      expect(t.activeHpp, 0);
      expect(t.gmv, 20000 + 20000);
    });
  });

  group('Account safety', () {
    test('same order_id in different accounts is not merged for compensation', () {
      final a = _order(id: 1, accountId: 1, orderId: 'SHARED', orderStatus: OrderStatus.returned, returnShippingCompensation: 10000);
      final b = _order(id: 2, accountId: 2, orderId: 'SHARED', orderStatus: OrderStatus.returned, returnShippingCompensation: 25000);
      final totals = ReturnTotals.fromJoined([
        _join(a, _item(orderId: 'SHARED', quantity: 1)),
        _join(b, _item(orderId: 'SHARED', quantity: 2)),
      ]);
      expect(totals.returnedCount, 2);
      expect(totals.returnedQty, 3);
      expect(totals.totalCompensation, 35000);
    });
  });

  group('Transitional fromTransactions wrappers', () {
    test('ReportTotals.fromTransactions single-item equivalent to fromJoined', () {
      final single = _item(orderId: 'O1', unitPrice: 50000, quantity: 2, hppUnitAmount: 20000, netIncomeAmount: 90000);
      final legacy = ReportTotals.fromTransactions([single]);
      final joined = ReportTotals.fromJoined([_join(_order(orderId: 'O1'), single)]);
      expect(legacy.gmv, joined.gmv);
      expect(legacy.netIncome, joined.netIncome);
      expect(legacy.hpp, joined.hpp);
      expect(legacy.profit, joined.profit);
    });

    test('ReturnTotals.fromTransactions single-item equivalent to fromJoined', () {
      final single = _item(orderId: 'R', unitPrice: 10000, quantity: 1, netIncomeAmount: 8000);
      final legacy = ReturnTotals.fromTransactions([single]);
      final joined = ReturnTotals.fromJoined([_join(_order(orderId: 'R'), single)]);
      expect(legacy.returnedCount, joined.returnedCount);
      expect(legacy.returnedQty, joined.returnedQty);
      expect(legacy.totalCompensation, joined.totalCompensation);
      expect(legacy.activeIncome, joined.activeIncome);
      expect(legacy.activeHpp, joined.activeHpp);
    });

    test('DashboardTotals.fromTransactions single-item equivalent to fromJoined', () {
      final single = _item(orderId: 'O1', unitPrice: 20000, quantity: 3, hppUnitAmount: 5000, netIncomeAmount: 55000);
      final legacy = DashboardTotals.fromTransactions([single]);
      final joined = DashboardTotals.fromJoined([_join(_order(orderId: 'O1'), single)]);
      expect(legacy.itemsSold, joined.itemsSold);
      expect(legacy.gmv, joined.gmv);
      expect(legacy.activeIncome, joined.activeIncome);
      expect(legacy.activeHpp, joined.activeHpp);
      expect(legacy.profit, joined.profit);
    });
  });
}