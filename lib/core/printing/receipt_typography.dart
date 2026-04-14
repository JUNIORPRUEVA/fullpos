import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class ReceiptTypography {
  ReceiptTypography._();

  static const String fontFamily = 'ReceiptFont';

  static final TextStyle receiptTextStyle = const TextStyle(
    fontFamily: fontFamily,
    fontSize: 10,
    color: Colors.black87,
    letterSpacing: 0.2,
    height: 1.1,
  );

  static final TextStyle receiptDetailStyle = receiptTextStyle.copyWith(
    fontSize: 11.5,
    fontWeight: FontWeight.w500,
  );

  static final TextStyle receiptTotalStyle = receiptTextStyle.copyWith(
    fontSize: 13.5,
    fontWeight: FontWeight.w600,
  );

  static final NumberFormat currencyFormat = NumberFormat('#,##0.00');

  static String money(num value) => currencyFormat.format(value);
}