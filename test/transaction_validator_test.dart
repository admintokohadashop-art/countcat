import 'package:flutter_test/flutter_test.dart';
import 'package:tiktok_seller/data/models/statuses.dart';
import 'package:tiktok_seller/features/sales/transaction_validator.dart';

void main() {
  group('TransactionValidator.unitPrice', () {
    test('null is invalid', () {
      expect(TransactionValidator.unitPrice(null), isNotNull);
    });
    test('0 is invalid', () {
      expect(TransactionValidator.unitPrice(0), isNotNull);
    });
    test('negative is invalid', () {
      expect(TransactionValidator.unitPrice(-1), isNotNull);
    });
    test('positive is valid', () {
      expect(TransactionValidator.unitPrice(1), isNull);
      expect(TransactionValidator.unitPrice(50000), isNull);
    });
  });

  group('TransactionValidator regressions', () {
    test('quantity still requires >= 1', () {
      expect(TransactionValidator.quantity('0'), isNotNull);
      expect(TransactionValidator.quantity('1'), isNull);
      expect(TransactionValidator.quantity('abc'), isNotNull);
    });
    test('productCode and orderId still required', () {
      expect(TransactionValidator.productCode(''), isNotNull);
      expect(TransactionValidator.orderId(''), isNotNull);
    });
    test('paidAt still requires a date when paid', () {
      expect(TransactionValidator.paidAt(PaymentStatus.paid, null), isNotNull);
      expect(TransactionValidator.paidAt(PaymentStatus.pending, null), isNull);
    });
    test('normalizePaidAt still clears for non-paid', () {
      expect(TransactionValidator.normalizePaidAt(PaymentStatus.pending, DateTime.now()), isNull);
      expect(TransactionValidator.normalizePaidAt(PaymentStatus.cancelled, DateTime.now()), isNull);
    });
  });
}