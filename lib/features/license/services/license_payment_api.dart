import 'dart:convert';

import '../../../core/network/api_client.dart';

class LicensePaymentException implements Exception {
  final int statusCode;
  final String message;

  const LicensePaymentException({
    required this.statusCode,
    required this.message,
  });

  @override
  String toString() =>
      'LicensePaymentException(status=$statusCode message=$message)';
}

class LicenseBillingInfo {
  final String projectCode;
  final String projectName;
  final double monthlyPrice;
  final String currency;
  final int demoDays;
  final int minPurchaseMonths;
  final bool isPaidProject;
  final bool allowDemo;
  final bool isActive;

  const LicenseBillingInfo({
    required this.projectCode,
    required this.projectName,
    required this.monthlyPrice,
    required this.currency,
    required this.demoDays,
    required this.minPurchaseMonths,
    required this.isPaidProject,
    required this.allowDemo,
    required this.isActive,
  });

  factory LicenseBillingInfo.fromJson(Map<String, dynamic> map) {
    return LicenseBillingInfo(
      projectCode: (map['project_code'] ?? '').toString().trim(),
      projectName: (map['project_name'] ?? '').toString().trim(),
      monthlyPrice: (map['monthly_price'] as num?)?.toDouble() ?? 0,
      currency: (map['currency'] ?? 'USD').toString().trim(),
      demoDays: (map['demo_days'] as num?)?.toInt() ?? 0,
      minPurchaseMonths: (map['min_purchase_months'] as num?)?.toInt() ?? 1,
      isPaidProject: map['is_paid_project'] == true,
      allowDemo: map['allow_demo'] == true,
      isActive: map['is_active'] == true,
    );
  }
}

class LicensePaymentOrder {
  final String paymentOrderId;
  final String paypalOrderId;
  final String checkoutUrl;
  final double amount;
  final String currency;
  final int months;
  final double monthlyPrice;

  const LicensePaymentOrder({
    required this.paymentOrderId,
    required this.paypalOrderId,
    required this.checkoutUrl,
    required this.amount,
    required this.currency,
    required this.months,
    required this.monthlyPrice,
  });

  factory LicensePaymentOrder.fromJson(Map<String, dynamic> map) {
    return LicensePaymentOrder(
      paymentOrderId: (map['payment_order_id'] ?? '').toString().trim(),
      paypalOrderId: (map['paypal_order_id'] ?? '').toString().trim(),
      checkoutUrl:
          (map['preferred_checkout_url'] ??
                  map['card_checkout_url'] ??
                  map['checkout_url'] ??
                  '')
              .toString()
              .trim(),
      amount: (map['amount'] as num?)?.toDouble() ?? 0,
      currency: (map['currency'] ?? 'USD').toString().trim(),
      months: (map['months'] as num?)?.toInt() ?? 0,
      monthlyPrice: (map['monthly_price'] as num?)?.toDouble() ?? 0,
    );
  }
}

class LicenseCaptureResult {
  final bool success;
  final bool paymentCaptured;
  final String? paymentOrderId;
  final String? paypalOrderId;
  final String? message;

  const LicenseCaptureResult({
    required this.success,
    required this.paymentCaptured,
    required this.paymentOrderId,
    required this.paypalOrderId,
    required this.message,
  });

  factory LicenseCaptureResult.fromJson(Map<String, dynamic> map) {
    return LicenseCaptureResult(
      success: map['success'] == true,
      paymentCaptured: map['payment_captured'] == true,
      paymentOrderId: map['payment_order_id']?.toString(),
      paypalOrderId: map['paypal_order_id']?.toString(),
      message: map['message']?.toString(),
    );
  }
}

class LicensePaymentApi {
  LicensePaymentApi();

  Future<Map<String, dynamic>> _getJsonMap(
    ApiClient api,
    String path, {
    Map<String, String>? queryParameters,
  }) async {
    final res = await api.get(
      path,
      queryParameters: queryParameters,
      timeout: const Duration(seconds: 10),
      retry: true,
    );
    final decoded = jsonDecode(res.body);
    if (decoded is! Map<String, dynamic>) {
      throw LicensePaymentException(
        statusCode: res.statusCode,
        message: 'Respuesta inválida del servidor.',
      );
    }
    if (res.statusCode < 200 ||
        res.statusCode >= 300 ||
        decoded['success'] == false) {
      throw LicensePaymentException(
        statusCode: res.statusCode,
        message: (decoded['message'] ?? 'Operación no disponible').toString(),
      );
    }
    return decoded;
  }

  Future<Map<String, dynamic>> _postJsonMap(
    ApiClient api,
    String path, {
    required Map<String, dynamic> body,
  }) async {
    final res = await api.postJson(
      path,
      body: body,
      timeout: const Duration(seconds: 12),
      retry: false,
      throwOnServerError: false,
    );
    final decoded = jsonDecode(res.body);
    if (decoded is! Map<String, dynamic>) {
      throw LicensePaymentException(
        statusCode: res.statusCode,
        message: 'Respuesta inválida del servidor.',
      );
    }
    if (res.statusCode < 200 ||
        res.statusCode >= 300 ||
        decoded['success'] == false) {
      throw LicensePaymentException(
        statusCode: res.statusCode,
        message: (decoded['message'] ?? 'Operación no disponible').toString(),
      );
    }
    return decoded;
  }

  Future<LicenseBillingInfo> getBillingInfo({
    required String baseUrl,
    required String projectCode,
  }) async {
    final api = ApiClient(baseUrl: baseUrl);
    try {
      final json = await _getJsonMap(
        api,
        '/api/public/projects/$projectCode/billing',
      );
      return LicenseBillingInfo.fromJson(json);
    } on LicensePaymentException catch (e) {
      if (e.statusCode != 404) rethrow;
    }
    final fallback = await _getJsonMap(
      api,
      '/public/projects/$projectCode/billing',
    );
    return LicenseBillingInfo.fromJson(fallback);
  }

  Future<LicensePaymentOrder> createPaypalOrder({
    required String baseUrl,
    required String projectCode,
    required String deviceId,
    required int months,
    String? businessId,
    required String businessName,
    required String businessType,
    required String ownerName,
    required String phone,
    String? email,
  }) async {
    final body = <String, dynamic>{
      'project_code': projectCode,
      'device_id': deviceId,
      'months': months,
      if ((businessId ?? '').trim().isNotEmpty)
        'business_id': businessId!.trim(),
      'business_name': businessName.trim(),
      'business_type': businessType.trim(),
      'owner_name': ownerName.trim(),
      'phone': phone.trim(),
      if ((email ?? '').trim().isNotEmpty) 'email': email!.trim(),
    };
    final api = ApiClient(baseUrl: baseUrl);
    try {
      final json = await _postJsonMap(
        api,
        '/api/public/license-payments/create-paypal-order',
        body: body,
      );
      return LicensePaymentOrder.fromJson(json);
    } on LicensePaymentException catch (e) {
      if (e.statusCode != 404) rethrow;
    }
    final fallback = await _postJsonMap(
      api,
      '/public/license-payments/create-paypal-order',
      body: body,
    );
    return LicensePaymentOrder.fromJson(fallback);
  }

  Future<LicenseCaptureResult> capturePaypalOrder({
    required String baseUrl,
    required String paymentOrderId,
    required String paypalOrderId,
  }) async {
    final body = <String, dynamic>{
      'payment_order_id': paymentOrderId,
      'paypal_order_id': paypalOrderId,
    };
    final api = ApiClient(baseUrl: baseUrl);
    try {
      final json = await _postJsonMap(
        api,
        '/api/public/license-payments/capture-paypal-order',
        body: body,
      );
      return LicenseCaptureResult.fromJson(json);
    } on LicensePaymentException catch (e) {
      if (e.statusCode != 404) rethrow;
    }
    final fallback = await _postJsonMap(
      api,
      '/public/license-payments/capture-paypal-order',
      body: body,
    );
    return LicenseCaptureResult.fromJson(fallback);
  }
}
