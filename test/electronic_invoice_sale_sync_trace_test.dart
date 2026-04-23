import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fullpos/core/db/app_db.dart';
import 'package:fullpos/core/db/db_init.dart';
import 'package:fullpos/core/logging/app_logger.dart';
import 'package:fullpos/core/session/session_manager.dart';
import 'package:fullpos/features/facturacion_electronica/data/factura_electronica_repository.dart';
import 'package:fullpos/features/facturacion_electronica/data/models/factura_electronica_model.dart';
import 'package:fullpos/features/sales/data/sales_repository.dart';
import 'package:fullpos/features/settings/data/business_settings_model.dart';
import 'package:fullpos/features/settings/data/business_settings_repository.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePathProviderPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  _FakePathProviderPlatform(this._docsDir);

  final Directory _docsDir;

  @override
  Future<String?> getApplicationDocumentsPath() async => _docsDir.path;

  @override
  Future<String?> getApplicationSupportPath() async =>
      p.join(_docsDir.path, 'support');

  @override
  Future<String?> getLibraryPath() async => _docsDir.path;
}

class _AllowRealHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory docsDir;

  setUpAll(() async {
    DbInit.ensureInitialized();
    docsDir = await Directory.systemTemp.createTemp('fullpos_fe_sale_sync_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(docsDir);
    SharedPreferences.setMockInitialValues({});
  });

  tearDownAll(() async {
    await AppDb.resetForTests();
    try {
      await docsDir.delete(recursive: true);
    } catch (_) {}
  });

  test(
    'invoice E32 sale syncs to cloud before FE generate even with inactive session',
    () async {
      await HttpOverrides.runZoned(() async {
        await AppDb.resetForTests();
        SharedPreferences.setMockInitialValues({});
        await SessionManager.logout();

        final requestOrder = <String>[];
        final requestBodies = <String, Map<String, dynamic>>{};
        final remoteSales = <String, int>{};
        var nextRemoteSaleId = 9000;
        Map<String, dynamic>? generatedInvoice;

        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        server.listen((request) async {
        final path = request.uri.path;
        requestOrder.add('${request.method} $path');

        String bodyText = '';
        if (request.method != 'GET') {
          bodyText = await utf8.decoder.bind(request).join();
        }
        final body = bodyText.trim().isEmpty
            ? <String, dynamic>{}
            : Map<String, dynamic>.from(jsonDecode(bodyText) as Map);
        requestBodies['${request.method} $path'] = body;

        request.response.headers.contentType = ContentType.json;

        if (request.method == 'POST' && path == '/api/sales/sync/by-rnc') {
          final sales = (body['sales'] as List<dynamic>? ?? const [])
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList(growable: false);
          final results = <Map<String, dynamic>>[];
          for (final sale in sales) {
            final localCode = sale['localCode']?.toString() ?? '';
            if (localCode.isEmpty) continue;
            final remoteSaleId = remoteSales.putIfAbsent(
              localCode,
              () => nextRemoteSaleId++,
            );
            results.add({
              'id': remoteSaleId,
              'localCode': localCode,
              'status': sale['status']?.toString() ?? 'completed',
              'kind': sale['kind']?.toString() ?? 'invoice',
            });
          }
          request.response.statusCode = 200;
          request.response.write(
            jsonEncode({
              'ok': true,
              'upserted': sales.length,
              'companyId': 77,
              'results': results,
            }),
          );
          await request.response.close();
          return;
        }

        if (request.method == 'POST' &&
            path == '/api/electronic-invoicing/outbound/generate/by-rnc') {
          final saleLocalCode = body['saleLocalCode']?.toString() ?? '';
          final remoteSaleId = remoteSales[saleLocalCode];
          if (remoteSaleId == null) {
            request.response.statusCode = 404;
            request.response.write(
              jsonEncode({
                'message': 'Venta no encontrada',
                'errorCode': 'SALE_NOT_FOUND',
              }),
            );
            await request.response.close();
            return;
          }

          generatedInvoice = {
            'id': 501,
            'saleId': remoteSaleId,
            'saleLocalCode': saleLocalCode,
            'ecf': 'E320000000001',
            'documentTypeCode': '32',
            'internalStatus': 'GENERATED',
            'dgiiStatus': 'PENDING',
            'totalAmount': 250.0,
            'buyerName': 'CONSUMIDOR FINAL',
            'buyerRnc': null,
            'createdAt': '2026-04-23T10:00:00.000Z',
            'updatedAt': '2026-04-23T10:00:00.000Z',
          };
          request.response.statusCode = 201;
          request.response.write(jsonEncode(generatedInvoice));
          await request.response.close();
          return;
        }

        if (request.method == 'POST' &&
            path == '/api/electronic-invoicing/outbound/sign/by-rnc') {
          generatedInvoice = {
            ...?generatedInvoice,
            'xmlSigned': '<eCF><Signature/></eCF>',
            'internalStatus': 'SIGNED',
            'updatedAt': '2026-04-23T10:01:00.000Z',
          };
          request.response.statusCode = 200;
          request.response.write(jsonEncode(generatedInvoice));
          await request.response.close();
          return;
        }

        if (request.method == 'POST' &&
            path == '/api/electronic-invoicing/outbound/submit/by-rnc') {
          generatedInvoice = {
            ...?generatedInvoice,
            'dgiiTrackId': 'TRK-E32-001',
            'dgiiStatus': 'ACCEPTED',
            'internalStatus': 'SUBMITTED',
            'submittedAt': '2026-04-23T10:02:00.000Z',
            'updatedAt': '2026-04-23T10:02:00.000Z',
          };
          request.response.statusCode = 200;
          request.response.write(jsonEncode(generatedInvoice));
          await request.response.close();
          return;
        }

        if (request.method == 'GET' &&
            path == '/api/electronic-invoicing/outbound/by-rnc') {
          request.response.statusCode = 200;
          request.response.write(
            jsonEncode([
              {
                'id': generatedInvoice?['id'] ?? 501,
                'saleId': generatedInvoice?['saleId'] ?? 9000,
                'saleLocalCode': generatedInvoice?['saleLocalCode'] ??
                    'VENTA-E32-001',
                'documentNumber': generatedInvoice?['ecf'] ?? 'E320000000001',
                'documentTypeCode': '32',
                'internalStatus': generatedInvoice?['internalStatus'] ??
                    'SUBMITTED',
                'dgiiTrackId': generatedInvoice?['dgiiTrackId'] ??
                    'TRK-E32-001',
                'dgiiStatus': generatedInvoice?['dgiiStatus'] ?? 'ACCEPTED',
                'totalAmount': 250.0,
                'customerName': 'CONSUMIDOR FINAL',
                'customerRnc': null,
                'documentLabel': 'Factura de consumo',
                'createdAt': '2026-04-23T10:02:00.000Z',
                'referenceDocument': null,
              },
            ]),
          );
          await request.response.close();
          return;
        }

        request.response.statusCode = 404;
        request.response.write(jsonEncode({'message': 'not found'}));
        await request.response.close();
      });

        try {
          await BusinessSettingsRepository().loadSettings();
          await BusinessSettingsRepository().saveSettings(
            BusinessSettings(
              businessName: 'FULLPOS SRL',
              rnc: '101010101',
              address: 'Santo Domingo',
              electronicInvoicingEnabled: true,
              cloudEnabled: true,
              cloudEndpoint: 'http://127.0.0.1:${server.port}',
              cloudApiKey: 'test-key',
              cloudCompanyId: 'fp-cloud-77',
            ),
          );

          final saleId = await SalesRepository.createSale(
            localCode: 'VENTA-E32-001',
            kind: 'invoice',
            items: const [
              {
                'product_code_snapshot': 'P-001',
                'product_name_snapshot': 'Producto FE',
                'qty': 1.0,
                'unit_price': 250.0,
                'purchase_price_snapshot': 100.0,
                'discount_line': 0.0,
                'total_line': 250.0,
              },
            ],
            itbisEnabled: false,
            subtotalOverride: 250.0,
            itbisAmountOverride: 0.0,
            totalOverride: 250.0,
            paymentMethod: 'cash',
            paymentCashAmount: 250.0,
            paymentCardAmount: 0.0,
            paymentTransferAmount: 0.0,
            paidAmount: 250.0,
            changeAmount: 0.0,
            electronicInvoiceEnabled: true,
            electronicDocumentType: '32',
            customerName: 'CONSUMIDOR FINAL',
          );

          final factura = await FacturaElectronicaRepository.getBySaleId(saleId);
          final recent = await FacturaElectronicaRepository.loadRecentResolved(
            limit: 10,
          );
          final logPath = await AppLogger.instance.exportLatestLogs();
          final logs = logPath == null ? '' : await File(logPath).readAsString();

          expect(await SessionManager.isLoggedIn(), isFalse);
          expect(remoteSales['VENTA-E32-001'], isNotNull);
          expect(
            requestOrder,
            containsAllInOrder([
              'POST /api/sales/sync/by-rnc',
              'POST /api/electronic-invoicing/outbound/generate/by-rnc',
              'POST /api/electronic-invoicing/outbound/sign/by-rnc',
              'POST /api/electronic-invoicing/outbound/submit/by-rnc',
            ]),
          );

          expect(
            requestBodies['POST /api/electronic-invoicing/outbound/generate/by-rnc']?['saleId'],
            saleId,
          );
          expect(
            requestBodies['POST /api/electronic-invoicing/outbound/generate/by-rnc']?['saleLocalCode'],
            'VENTA-E32-001',
          );
          expect(
            requestBodies['POST /api/electronic-invoicing/outbound/generate/by-rnc']?['companyCloudId'],
            'fp-cloud-77',
          );
          expect(
            requestBodies['POST /api/electronic-invoicing/outbound/generate/by-rnc']?['companyRnc'],
            '101010101',
          );

          expect(factura, isNotNull);
          expect(factura!.ecf, 'E320000000001');
          expect(factura.dgiiTrackId, 'TRK-E32-001');
          expect(factura.estadoInterno, 'SUBMITTED');

          expect(recent, isNotEmpty);
          expect(recent.first.ecf, 'E320000000001');
          expect(recent.first.localCode, 'VENTA-E32-001');

          expect(logs, contains('createSale saved local saleId=$saleId'));
          expect(logs, contains('Cloud sales sync response reason=electronic_invoice_presubmit_sync_sale_$saleId'));
          expect(logs, contains('tracedRemoteSaleId=${remoteSales['VENTA-E32-001']}'));
          expect(logs, contains('FE generate request saleId=$saleId saleLocalCode=VENTA-E32-001'));
          expect(
            logs,
            contains(
              'payload={\\"companyCloudId\\":\\"fp-cloud-77\\",\\"companyRnc\\":\\"101010101\\",\\"saleId\\":$saleId,\\"saleLocalCode\\":\\"VENTA-E32-001\\",\\"documentTypeCode\\":\\"32\\",\\"branchId\\":0}',
            ),
          );
        } finally {
          await server.close(force: true);
        }
      }, createHttpClient: _AllowRealHttpOverrides().createHttpClient);
    },
  );

  test(
    'after submit with trackId pending, app queries result/by-rnc and persists final status',
    () async {
      await HttpOverrides.runZoned(() async {
        await AppDb.resetForTests();
        SharedPreferences.setMockInitialValues({});
        await SessionManager.logout();

        final requestOrder = <String>[];
        final remoteSales = <String, int>{};
        Map<String, dynamic>? generatedInvoice;
        var resultQueried = 0;

        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        server.listen((request) async {
          final path = request.uri.path;
          requestOrder.add('${request.method} $path');

          String bodyText = '';
          if (request.method != 'GET') {
            bodyText = await utf8.decoder.bind(request).join();
          }
          final body = bodyText.trim().isEmpty
              ? <String, dynamic>{}
              : Map<String, dynamic>.from(jsonDecode(bodyText) as Map);

          request.response.headers.contentType = ContentType.json;

          if (request.method == 'POST' && path == '/api/sales/sync/by-rnc') {
            final sales = (body['sales'] as List<dynamic>? ?? const [])
                .whereType<Map>()
                .map((row) => Map<String, dynamic>.from(row))
                .toList(growable: false);
            for (final sale in sales) {
              final localCode = sale['localCode']?.toString() ?? '';
              if (localCode.isEmpty) continue;
              remoteSales[localCode] = 9100;
            }
            request.response.statusCode = 200;
            request.response.write(
              jsonEncode({
                'ok': true,
                'upserted': sales.length,
                'companyId': 77,
                'results': [
                  {
                    'id': 9100,
                    'localCode': 'VENTA-E32-002',
                    'status': 'completed',
                    'kind': 'invoice',
                  },
                ],
              }),
            );
            await request.response.close();
            return;
          }

          if (request.method == 'POST' &&
              path == '/api/electronic-invoicing/outbound/generate/by-rnc') {
            generatedInvoice = {
              'id': 601,
              'saleId': 9100,
              'saleLocalCode': 'VENTA-E32-002',
              'ecf': 'E320000000002',
              'documentTypeCode': '32',
              'internalStatus': 'GENERATED',
              'dgiiStatus': 'PENDING',
              'totalAmount': 100.0,
              'buyerName': 'CONSUMIDOR FINAL',
              'createdAt': '2026-04-23T10:10:00.000Z',
              'updatedAt': '2026-04-23T10:10:00.000Z',
            };
            request.response.statusCode = 201;
            request.response.write(jsonEncode(generatedInvoice));
            await request.response.close();
            return;
          }

          if (request.method == 'POST' &&
              path == '/api/electronic-invoicing/outbound/sign/by-rnc') {
            generatedInvoice = {
              ...?generatedInvoice,
              'xmlSigned': '<eCF><Signature/></eCF>',
              'internalStatus': 'SIGNED',
              'updatedAt': '2026-04-23T10:11:00.000Z',
            };
            request.response.statusCode = 200;
            request.response.write(jsonEncode(generatedInvoice));
            await request.response.close();
            return;
          }

          if (request.method == 'POST' &&
              path == '/api/electronic-invoicing/outbound/submit/by-rnc') {
            generatedInvoice = {
              ...?generatedInvoice,
              'dgiiTrackId': 'TRK-E32-002',
              'dgiiStatus': 'IN_PROCESS',
              'internalStatus': 'SUBMITTED',
              'submittedAt': '2026-04-23T10:12:00.000Z',
              'updatedAt': '2026-04-23T10:12:00.000Z',
            };
            request.response.statusCode = 200;
            request.response.write(jsonEncode(generatedInvoice));
            await request.response.close();
            return;
          }

          if (request.method == 'GET' &&
              path ==
                  '/api/electronic-invoicing/outbound/result/by-rnc/TRK-E32-002') {
            resultQueried += 1;
            final invoice = {
              ...?generatedInvoice,
              'dgiiStatus': 'ACCEPTED',
              'internalStatus': 'ACCEPTED',
              'acceptedAt': '2026-04-23T10:12:10.000Z',
              'updatedAt': '2026-04-23T10:12:10.000Z',
            };
            request.response.statusCode = 200;
            request.response.write(jsonEncode({'invoice': invoice}));
            await request.response.close();
            return;
          }

          request.response.statusCode = 404;
          request.response.write(jsonEncode({'message': 'not found'}));
          await request.response.close();
        });

        try {
          await BusinessSettingsRepository().saveSettings(
            BusinessSettings(
              businessName: 'FULLPOS SRL',
              rnc: '101010101',
              address: 'Santo Domingo',
              electronicInvoicingEnabled: true,
              cloudEnabled: true,
              cloudEndpoint: 'http://127.0.0.1:${server.port}',
              cloudApiKey: 'test-key',
              cloudCompanyId: 'fp-cloud-77',
            ),
          );

          final saleId = await SalesRepository.createSale(
            localCode: 'VENTA-E32-002',
            kind: 'invoice',
            items: const [
              {
                'product_code_snapshot': 'P-001',
                'product_name_snapshot': 'Producto FE',
                'qty': 1.0,
                'unit_price': 100.0,
                'purchase_price_snapshot': 50.0,
                'discount_line': 0.0,
                'total_line': 100.0,
              },
            ],
            itbisEnabled: false,
            subtotalOverride: 100.0,
            itbisAmountOverride: 0.0,
            totalOverride: 100.0,
            paymentMethod: 'cash',
            paymentCashAmount: 100.0,
            paymentCardAmount: 0.0,
            paymentTransferAmount: 0.0,
            paidAmount: 100.0,
            changeAmount: 0.0,
            electronicInvoiceEnabled: true,
            electronicDocumentType: '32',
            customerName: 'CONSUMIDOR FINAL',
          );

          final factura = await FacturaElectronicaRepository.getBySaleId(saleId);
          final logPath = await AppLogger.instance.exportLatestLogs();
          final logs = logPath == null ? '' : await File(logPath).readAsString();

          expect(factura, isNotNull);
          expect(factura!.dgiiTrackId, 'TRK-E32-002');
          expect(factura.estadoDgii, FacturaElectronicaModel.statusAccepted);

          expect(
            requestOrder,
            containsAllInOrder([
              'POST /api/sales/sync/by-rnc',
              'POST /api/electronic-invoicing/outbound/generate/by-rnc',
              'POST /api/electronic-invoicing/outbound/sign/by-rnc',
              'POST /api/electronic-invoicing/outbound/submit/by-rnc',
              'GET /api/electronic-invoicing/outbound/result/by-rnc/TRK-E32-002',
            ]),
          );
          expect(resultQueried, 1);
          expect(logs, contains('FE trackId received trackId=TRK-E32-002'));
          expect(
            logs,
            contains(
              'FE dgii result query path=/api/electronic-invoicing/outbound/result/by-rnc/TRK-E32-002',
            ),
          );
        } finally {
          await server.close(force: true);
        }
      }, createHttpClient: _AllowRealHttpOverrides().createHttpClient);
    },
  );
}