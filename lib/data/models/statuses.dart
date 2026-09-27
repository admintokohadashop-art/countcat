enum PaymentStatus {
  pending('pending', 'MENUNGGU PEMBAYARAN'),
  paid('paid', 'SUDAH DIBAYAR'),
  cancelled('cancelled', 'DIBATALKAN');

  const PaymentStatus(this.value, this.label);
  final String value;
  final String label;
  static PaymentStatus fromValue(String value) => values.firstWhere((status) => status.value == value);
}

enum OrderStatus {
  newOrder('new', 'BARU'),
  dropoff('dropoff', 'DROP OFF'),
  shipping('shipping', 'DALAM PENGIRIMAN'),
  closed('closed', 'CLOSE'),
  returned('returned', 'RETUR');

  const OrderStatus(this.value, this.label);
  final String value;
  final String label;
  static OrderStatus fromValue(String value) => values.firstWhere((status) => status.value == value);
}
