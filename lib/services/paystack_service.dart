import 'dart:convert';
import 'api_service.dart';

class PaystackService {
  final ApiService _api;

  PaystackService(this._api);

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'X-Api-Key': ApiService.appApiKey,
        if (_api.isAuthenticated) 'Authorization': 'Bearer ${_api.token}',
      };

  Future<PaystackInitResult> initializePayment({
    required String planId,
    required String email,
  }) async {
    final resp = await _api.post(
      '/api/paystack/initialize',
      headers: _headers,
      body: {'plan_id': planId, 'email': email},
    );

    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      final data = jsonDecode(resp.body);
      return PaystackInitResult(
        authorizationUrl: data['authorization_url'],
        reference: data['reference'],
        accessCode: data['access_code'],
      );
    }

    final error = jsonDecode(resp.body);
    throw Exception(error['detail'] ?? 'Payment initialization failed');
  }

  Future<PaystackVerifyResult> verifyPayment({
    required String reference,
    required String planId,
  }) async {
    final resp = await _api.post(
      '/api/paystack/verify',
      headers: _headers,
      body: {'reference': reference, 'plan_id': planId},
    );

    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      final data = jsonDecode(resp.body);
      return PaystackVerifyResult(
        success: data['success'] ?? false,
        message: data['message'] ?? '',
        reference: data['reference'] ?? '',
        expiresAt: data['expires_at'] != null
            ? DateTime.tryParse(data['expires_at'])
            : null,
      );
    }

    String detail = 'Verification failed';
    try {
      final body = jsonDecode(resp.body);
      detail = body['detail'] ?? body['message'] ?? detail;
    } catch (_) {}
    throw Exception(detail);
  }
}

class PaystackInitResult {
  final String authorizationUrl;
  final String reference;
  final String accessCode;

  PaystackInitResult({
    required this.authorizationUrl,
    required this.reference,
    required this.accessCode,
  });
}

class PaystackVerifyResult {
  final bool success;
  final String message;
  final String reference;
  final DateTime? expiresAt;

  PaystackVerifyResult({
    required this.success,
    required this.message,
    required this.reference,
    this.expiresAt,
  });
}
