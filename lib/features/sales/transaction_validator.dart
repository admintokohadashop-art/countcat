import '../../data/models/statuses.dart';

class TransactionValidator {
  static String? productCode(String? value) => value == null || value.trim().isEmpty ? 'Kode Barang wajib diisi.' : null;
  static String? orderId(String? value) => value == null || value.trim().isEmpty ? 'ID Pesanan wajib diisi.' : null;
  static String? quantity(String? value) {
    final amount = int.tryParse(value ?? '');
    return amount == null || amount < 1 ? 'Qty harus berupa angka minimal 1.' : null;
  }
  static String? rupiah(int? amount, String label) => amount == null ? '$label harus berupa Rupiah valid.' : null;
  static String? unitPrice(int? amount) {
    if (amount == null) return 'Harga Jual harus berupa Rupiah valid.';
    if (amount <= 0) return 'Harga Jual harus lebih dari 0.';
    return null;
  }
  static String? paidAt(PaymentStatus status, DateTime? value) => status == PaymentStatus.paid && value == null ? 'Tanggal Dibayar wajib diisi.' : null;
  static DateTime? normalizePaidAt(PaymentStatus status, DateTime? value) => status == PaymentStatus.paid ? value?.toUtc() : null;
}