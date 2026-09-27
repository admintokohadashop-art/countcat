class Rupiah {
  static int? parse(String input) {
    final normalized = input.trim().replaceAll(RegExp('rp', caseSensitive: false), '').replaceAll('.', '').replaceAll(',', '');
    if (!RegExp(r'^\d+$').hasMatch(normalized)) return null;
    return int.tryParse(normalized);
  }

  static String format(int amount) {
    final digits = amount.toString();
    final groups = <String>[];
    for (var end = digits.length; end > 0; end -= 3) {
      groups.add(digits.substring(end - 3 < 0 ? 0 : end - 3, end));
    }
    return 'Rp${groups.reversed.join('.')}';
  }
}
