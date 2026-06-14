import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fullpos/core/network/api_client.dart';
import 'package:fullpos/features/auth/services/password_reset_service.dart';

void main() {
  group('PasswordResetService.confirmSupportToken', () {
    test('uses the deployed API route and normalizes the payload', () async {
      late http.Request capturedRequest;
      final client = MockClient((request) async {
        capturedRequest = request;
        return http.Response(
          jsonEncode({'ok': true}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final service = PasswordResetService(
        apiClient: ApiClient(
          baseUrl: 'https://license.example.com',
          client: client,
        ),
        businessIdLoader: () async => ' business-123 ',
      );

      await service.confirmSupportToken(
        username: ' Admin ',
        token: ' abcd-ef12 ',
      );

      expect(
        capturedRequest.url.toString(),
        'https://license.example.com/api/password-reset/support-token/confirm',
      );
      expect(jsonDecode(capturedRequest.body), {
        'business_id': 'business-123',
        'username': 'admin',
        'token': 'ABCD-EF12',
      });
    });

    test('uses the admin route for the 64-character panel token', () async {
      late http.Request capturedRequest;
      final client = MockClient((request) async {
        capturedRequest = request;
        return http.Response(
          jsonEncode({'ok': true}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final service = PasswordResetService(
        apiClient: ApiClient(
          baseUrl: 'https://license.example.com',
          client: client,
        ),
        businessIdLoader: () async => 'business-123',
      );
      const uppercaseToken =
          'BCA0506D3202B9244729E2C00BCCA172FFCB046C6E6CDE4CED9A35CAE27B0FC1';

      await service.confirmSupportToken(
        username: 'admin',
        token:
            '${uppercaseToken.substring(0, 32)} '
            '${uppercaseToken.substring(32)}',
      );

      expect(
        capturedRequest.url.toString(),
        'https://license.example.com/api/password-reset/admin-token/validate',
      );
      expect(jsonDecode(capturedRequest.body), {
        'business_id': 'business-123',
        'token': uppercaseToken.toLowerCase(),
      });
    });

    test(
      'surfaces the backend message without retrying another route',
      () async {
        var requestCount = 0;
        final client = MockClient((request) async {
          requestCount++;
          return http.Response(
            jsonEncode({'ok': false, 'message': 'Token inválido'}),
            400,
            headers: {'content-type': 'application/json'},
          );
        });
        final service = PasswordResetService(
          apiClient: ApiClient(
            baseUrl: 'https://license.example.com',
            client: client,
          ),
          businessIdLoader: () async => 'business-123',
        );

        await expectLater(
          service.confirmSupportToken(username: 'admin', token: 'bad-token'),
          throwsA(
            isA<Exception>().having(
              (error) => error.toString(),
              'message',
              contains('Token inválido'),
            ),
          ),
        );
        expect(requestCount, 1);
      },
    );

    test('does not contact the backend without a local business id', () async {
      var requestCount = 0;
      final client = MockClient((request) async {
        requestCount++;
        return http.Response('{}', 200);
      });
      final service = PasswordResetService(
        apiClient: ApiClient(
          baseUrl: 'https://license.example.com',
          client: client,
        ),
        businessIdLoader: () async => ' ',
      );

      await expectLater(
        service.confirmSupportToken(username: 'admin', token: 'token'),
        throwsA(isA<StateError>()),
      );
      expect(requestCount, 0);
    });
  });
}
