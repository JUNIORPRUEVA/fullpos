import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/services/app_configuration_service.dart';
import '../../features/products/models/product_model.dart';

class ProductCatalogPrinter {
  ProductCatalogPrinter._();

  static String _sanitizePdfText(String input) {
    var s = input.replaceAll('\u00A0', ' ');

    // Evitar caracteres que rompen las fuentes built-in (Helvetica) del paquete `pdf`.
    s = s
        .replaceAll('\u2022', '|') // bullet
        .replaceAll('\u2013', '-') // en-dash
        .replaceAll('\u2014', '-') // em-dash
        .replaceAll('\u2026', '...') // ellipsis
        .replaceAll('\u00B7', '-') // middle dot
        .replaceAll('\u00AD', ''); // soft hyphen

    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s;
  }

  static Future<Uint8List> generateCatalogPdf({
    required List<ProductModel> products,
    String? title,
  }) async {
    final settings = <String, dynamic>{
      'businessName': appConfigService.getBusinessName().trim(),
      'slogan': (appConfigService.getSlogan() ?? '').trim(),
      'website': (appConfigService.getWebsite() ?? '').trim(),
      'phone': (appConfigService.getPhone() ?? '').trim(),
      'phone2': (appConfigService.getPhone2() ?? '').trim(),
      'companyPhone': appConfigService.getCompanyPhone().trim(),
      'email': (appConfigService.getEmail() ?? '').trim(),
      'address': (appConfigService.getAddress() ?? '').trim(),
      'city': (appConfigService.getCity() ?? '').trim(),
      'logoPath': (appConfigService.getLogoPath() ?? '').trim(),
      'currencySymbol': appConfigService.getCurrencySymbol().trim(),
    };

    final productsData = products
        .map(
          (p) => <String, dynamic>{
            'name': p.name,
            'salePrice': p.salePrice,
            'imagePath': p.imagePath,
          },
        )
        .toList(growable: false);

    final payload = <String, dynamic>{
      'title': title,
      'settings': settings,
      'products': productsData,
    };

    return Isolate.run(() async => _generateCatalogPdfFromData(payload));
  }

  static Future<Uint8List> _generateCatalogPdfFromData(
    Map<String, dynamic> payload,
  ) async {
    final pdf = pw.Document();

    final settings = (payload['settings'] as Map).cast<String, dynamic>();
    final products = (payload['products'] as List)
        .cast<Map>()
        .map((m) => m.cast<String, dynamic>())
        .toList(growable: false);

    final businessName =
        _sanitizePdfText((settings['businessName'] as String? ?? '').trim());
    final slogan = _sanitizePdfText((settings['slogan'] as String? ?? '').trim());
    final website =
        _sanitizePdfText((settings['website'] as String? ?? '').trim());
    final phone = _sanitizePdfText((settings['phone'] as String? ?? '').trim());
    final phone2 = _sanitizePdfText((settings['phone2'] as String? ?? '').trim());
    final companyPhone =
        _sanitizePdfText((settings['companyPhone'] as String? ?? '').trim());
    final email = _sanitizePdfText((settings['email'] as String? ?? '').trim());
    final address =
        _sanitizePdfText((settings['address'] as String? ?? '').trim());
    final city = _sanitizePdfText((settings['city'] as String? ?? '').trim());
    final logoPath = (settings['logoPath'] as String? ?? '').trim();
    final currencySymbol = (settings['currencySymbol'] as String? ?? '').trim();
    final currency = NumberFormat('#,##0.00', 'en_US');

    final rawTitle =
        _sanitizePdfText((payload['title'] as String?)?.trim() ?? '');
    final effectiveTitle = rawTitle.isNotEmpty
        ? rawTitle
        : (businessName.isNotEmpty
              ? 'Catalogo de $businessName'
              : 'Catalogo de Productos');

    Future<pw.ImageProvider?> loadImage(String? path) async {
      final p = path?.trim();
      if (p == null || p.isEmpty) return null;
      try {
        final file = File(p);
        if (!await file.exists()) return null;
        final bytes = await file.readAsBytes();
        if (bytes.isEmpty) return null;
        return pw.MemoryImage(bytes);
      } catch (_) {
        return null;
      }
    }

    String money(num value) {
      final v = value.toDouble();
      final symbol = currencySymbol.isEmpty ? r'$' : currencySymbol;
      return '$symbol ${currency.format(v)}';
    }

    final sorted = [...products];
    sorted.sort(
      (a, b) => (a['name'] as String? ?? '').toLowerCase().compareTo(
        (b['name'] as String? ?? '').toLowerCase(),
      ),
    );

    final imagesByIndex = <int, pw.ImageProvider?>{};
    for (var i = 0; i < sorted.length; i++) {
      imagesByIndex[i] = await loadImage(sorted[i]['imagePath'] as String?);
    }

    final logoImage = await loadImage(logoPath);
    final dateLabel = DateFormat('dd/MM/yyyy').format(DateTime.now());

    List<pw.Widget> buildContactLines() {
      final lines = <String>[];

      final phones = <String>[];
      if (phone.isNotEmpty) phones.add(phone);
      if (phone2.isNotEmpty) phones.add(phone2);
      if (phones.isEmpty && companyPhone.isNotEmpty) phones.add(companyPhone);
      if (phones.isNotEmpty) {
        lines.add('Tel: ${phones.join(' / ')}');
      }
      if (email.isNotEmpty) {
        lines.add('Email: $email');
      }
      final addressParts = <String>[];
      if (address.isNotEmpty) addressParts.add(address);
      if (city.isNotEmpty) addressParts.add(city);
      if (addressParts.isNotEmpty) {
        lines.add(addressParts.join(' | '));
      }

      return lines
          .map(
            (t) => pw.Text(
              _sanitizePdfText(t),
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
            ),
          )
          .toList(growable: false);
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.all(28),
        build: (context) {
          final widgets = <pw.Widget>[];

          widgets.add(
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                if (logoImage != null) ...[
                  pw.Container(
                    width: 46,
                    height: 46,
                    decoration: pw.BoxDecoration(
                      color: PdfColors.grey100,
                      borderRadius: pw.BorderRadius.circular(10),
                      border: pw.Border.all(
                        color: PdfColors.grey300,
                        width: 0.8,
                      ),
                    ),
                    child: pw.ClipRRect(
                      horizontalRadius: 10,
                      verticalRadius: 10,
                      child: pw.Image(logoImage, fit: pw.BoxFit.cover),
                    ),
                  ),
                  pw.SizedBox(width: 12),
                ],
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        _sanitizePdfText(effectiveTitle),
                        style: pw.TextStyle(
                          fontSize: 18,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.teal900,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        'Te presentamos nuestros productos disponibles.',
                        style: const pw.TextStyle(
                          fontSize: 10,
                          color: PdfColors.grey800,
                        ),
                      ),
                      if (slogan.isNotEmpty) ...[
                        pw.SizedBox(height: 3),
                        pw.Text(
                          _sanitizePdfText(slogan),
                          style: pw.TextStyle(
                            fontSize: 9,
                            color: PdfColors.grey700,
                            fontStyle: pw.FontStyle.italic,
                          ),
                        ),
                      ],
                      pw.SizedBox(height: 6),
                      ...buildContactLines(),
                      if (website.isNotEmpty) ...[
                        pw.SizedBox(height: 3),
                        pw.UrlLink(
                          destination: website,
                          child: pw.Text(
                            'Link de acceso: $website',
                            style: const pw.TextStyle(
                              fontSize: 9,
                              color: PdfColors.blue,
                              decoration: pw.TextDecoration.underline,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.teal,
                    borderRadius: pw.BorderRadius.circular(6),
                  ),
                  child: pw.Text(
                    dateLabel,
                    style: pw.TextStyle(
                      color: PdfColors.white,
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          );

          widgets.add(pw.SizedBox(height: 10));
          widgets.add(pw.Divider(color: PdfColors.grey400));
          widgets.add(pw.SizedBox(height: 10));

          if (sorted.isEmpty) {
            widgets.add(pw.Text('No hay productos para mostrar.'));
            return widgets;
          }

          widgets.add(
            pw.Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (var i = 0; i < sorted.length; i++)
                  pw.Container(
                    width: (PdfPageFormat.letter.availableWidth - 12) / 2,
                    padding: const pw.EdgeInsets.all(10),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(
                        color: PdfColors.grey300,
                        width: 0.8,
                      ),
                      borderRadius: pw.BorderRadius.circular(8),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Container(
                          height: 130,
                          width: double.infinity,
                          decoration: pw.BoxDecoration(
                            color: PdfColors.grey100,
                            borderRadius: pw.BorderRadius.circular(6),
                            border: pw.Border.all(
                              color: PdfColors.grey300,
                              width: 0.6,
                            ),
                          ),
                          child: () {
                            final img = imagesByIndex[i];
                            if (img == null) {
                              return pw.Center(
                                child: pw.Text(
                                  'Sin imagen',
                                  style: const pw.TextStyle(
                                    fontSize: 9,
                                    color: PdfColors.grey600,
                                  ),
                                ),
                              );
                            }
                            return pw.ClipRRect(
                              horizontalRadius: 6,
                              verticalRadius: 6,
                              child: pw.Image(img, fit: pw.BoxFit.cover),
                            );
                          }(),
                        ),
                        pw.SizedBox(height: 8),
                        pw.Text(
                          _sanitizePdfText(
                            (sorted[i]['name'] as String? ?? '').trim(),
                          ),
                          style: pw.TextStyle(
                            fontSize: 11,
                            fontWeight: pw.FontWeight.bold,
                          ),
                          maxLines: 2,
                          overflow: pw.TextOverflow.clip,
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          'Precio: ${money(sorted[i]['salePrice'] as num? ?? 0)}',
                          style: pw.TextStyle(
                            fontSize: 10,
                            color: PdfColors.teal900,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          );

          return widgets;
        },
        footer: (context) {
          final leftLines = <String>[];
          final base = businessName.isNotEmpty
              ? 'Catalogo de productos en PDF de la empresa $businessName'
              : 'Catalogo de productos en PDF';
          leftLines.add(_sanitizePdfText(base));

          final contactParts = <String>[];
          final phones = <String>[];
          if (phone.isNotEmpty) phones.add(phone);
          if (phone2.isNotEmpty) phones.add(phone2);
          if (phones.isEmpty && companyPhone.isNotEmpty) {
            phones.add(companyPhone);
          }
          if (phones.isNotEmpty) contactParts.add('Tel: ${phones.join(' / ')}');
          if (email.isNotEmpty) contactParts.add(email);

          final addressParts = <String>[];
          if (address.isNotEmpty) addressParts.add(address);
          if (city.isNotEmpty) addressParts.add(city);
          if (addressParts.isNotEmpty) {
            contactParts.add(addressParts.join(' | '));
          }

          if (contactParts.isNotEmpty) {
            leftLines.add(_sanitizePdfText(contactParts.join(' | ')));
          }

          return pw.Container(
            margin: const pw.EdgeInsets.only(top: 12),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    mainAxisSize: pw.MainAxisSize.min,
                    children: [
                      for (final line in leftLines)
                        pw.Text(
                          _sanitizePdfText(line),
                          maxLines: 1,
                          overflow: pw.TextOverflow.clip,
                          style: const pw.TextStyle(
                            fontSize: 8,
                            color: PdfColors.grey700,
                          ),
                        ),
                    ],
                  ),
                ),
                pw.Text(
                  _sanitizePdfText(
                    'Pagina ${context.pageNumber} de ${context.pagesCount}',
                  ),
                  style: const pw.TextStyle(
                    fontSize: 9,
                    color: PdfColors.grey700,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    return pdf.save();
  }
}
