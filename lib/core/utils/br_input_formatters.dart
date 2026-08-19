import 'package:flutter/services.dart';

String _onlyDigits(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

/// Formats digits as they're typed into ###.###.###-##, discarding anything
/// past 11 digits. Only formats — [isValidCpf] does the actual check-digit
/// validation, run once on submit rather than on every keystroke.
class CpfInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = _onlyDigits(newValue.text);
    final capped = digits.length > 11 ? digits.substring(0, 11) : digits;
    final buf = StringBuffer();
    for (var i = 0; i < capped.length; i++) {
      if (i == 3 || i == 6) buf.write('.');
      if (i == 9) buf.write('-');
      buf.write(capped[i]);
    }
    return TextEditingValue(
      text: buf.toString(),
      selection: TextSelection.collapsed(offset: buf.length),
    );
  }
}

/// Formats digits as (00) 00000-0000, discarding anything past 11 digits
/// (BR mobile numbers: 2-digit DDD + 9-digit number).
class PhoneInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = _onlyDigits(newValue.text);
    final capped = digits.length > 11 ? digits.substring(0, 11) : digits;
    final buf = StringBuffer();
    for (var i = 0; i < capped.length; i++) {
      if (i == 0) buf.write('(');
      if (i == 2) buf.write(') ');
      if (i == 7) buf.write('-');
      buf.write(capped[i]);
    }
    return TextEditingValue(
      text: buf.toString(),
      selection: TextSelection.collapsed(offset: buf.length),
    );
  }
}

/// Standard two-check-digit CPF validation. An empty [raw] is always valid
/// (the field is optional) — only rejects non-empty, malformed input.
bool isValidCpf(String raw) {
  final digits = _onlyDigits(raw);
  if (digits.isEmpty) return true;
  if (digits.length != 11) return false;
  if (RegExp(r'^(\d)\1{10}$').hasMatch(digits)) return false;

  int calcCheckDigit(String base) {
    var sum = 0;
    var weight = base.length + 1;
    for (final ch in base.split('')) {
      sum += int.parse(ch) * weight;
      weight--;
    }
    final rem = sum % 11;
    return rem < 2 ? 0 : 11 - rem;
  }

  final base9 = digits.substring(0, 9);
  final d1 = calcCheckDigit(base9);
  final d2 = calcCheckDigit(base9 + d1.toString());
  return digits == '$base9$d1$d2';
}
