import 'package:flutter/foundation.dart';
import '../../../core/db/app_db.dart';
import '../../../core/db/tables.dart';
import 'quote_model.dart';
import 'sales_repository.dart';

/// Servicio para convertir cotizaciones en tickets pendientes
class QuoteToTicketConverter {
  /// Convierte una cotización a un ticket pendiente
  /// 
  /// Validaciones:
  /// - La cotización debe existir
  /// - No debe haber un ticket pendiente previo para esta cotización
  /// 
  /// Dentro de una transacción:
  /// - Crea un nuevo ticket POS
  /// - Copia todos los items
  /// - Actualiza el estado de la cotización a 'PASSED_TO_TICKET'
  /// 
  /// Retorna: ID del nuevo ticket creado
  /// Lanza excepciones si hay errores
  static Future<int> convertQuoteToTicket({
    required int quoteId,
    required int? userId,
  }) async {
    debugPrint('🔄 [CONVERTER] Iniciando conversión de cotización #$quoteId a ticket pendiente');
    
    final database = await AppDb.database;
    
    return await database.transaction((txn) async {
      try {
        // 1. VALIDAR: Obtener cotización completa
        debugPrint('📋 [CONVERTER] Paso 1: Obteniendo cotización #$quoteId');
        final quoteResults = await txn.rawQuery(
          'SELECT * FROM ${DbTables.quotes} WHERE id = ?',
          [quoteId],
        );
        
        if (quoteResults.isEmpty) {
          throw Exception('Cotización #$quoteId no encontrada');
        }
        
        final quoteMap = quoteResults.first;
        final quote = QuoteModel.fromMap(quoteMap);
        debugPrint('✅ [CONVERTER] Cotización encontrada: ${quote.ticketName}');
        
        // 2. VALIDAR: Verificar que la cotización no está ya convertida
        debugPrint('🔍 [CONVERTER] Paso 2: Verificando si ya fue convertida...');
        if (quote.status == 'PASSED_TO_TICKET') {
          throw Exception('Esta cotización ya fue convertida a ticket pendiente');
        }
        debugPrint('✅ [CONVERTER] Cotización no está convertida previamente');
        
        // 3. OBTENER ITEMS de la cotización
        debugPrint('📦 [CONVERTER] Paso 3: Obteniendo items de cotización');
        final itemResults = await txn.query(
          DbTables.quoteItems,
          where: 'quote_id = ?',
          whereArgs: [quoteId],
        );
        
        final items = itemResults
            .map((map) => QuoteItemModel.fromMap(map))
            .toList();
        debugPrint('✅ [CONVERTER] ${items.length} items encontrados');
        
        // 4. CREAR TICKET PENDIENTE
        debugPrint('🎫 [CONVERTER] Paso 4: Creando ticket pendiente');
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        
        // Generar código local único para el ticket
        final localCode = await SalesRepository.generateNextLocalCode('pending');
        debugPrint('📝 [CONVERTER] Código local generado: $localCode');
        
        final ticketName = quote.ticketName ?? 'Cotización #${quote.id}';
        final ticketId = await txn.insert(DbTables.posTickets, {
          'ticket_name': ticketName,
          'user_id': userId,
          'client_id': quote.clientId,
          'local_code': localCode,
          'itbis_enabled': quote.itbisEnabled ? 1 : 0,
          'itbis_rate': quote.itbisRate,
          'discount_total': quote.discountTotal,
          'created_at_ms': nowMs,
          'updated_at_ms': nowMs,
        });
        
        debugPrint('✅ [CONVERTER] Ticket creado con ID: $ticketId');
        
        // 5. COPIAR ITEMS al ticket
        debugPrint('📦 [CONVERTER] Paso 5: Copiando ${items.length} items al ticket');
        int itemsInserted = 0;
        for (final item in items) {
          // Obtener el código del producto desde quote_items (productCode)
          // Si no existe, usar el product_id convertido a string como fallback
          final codeSnapshot = item.productCode?.isNotEmpty == true 
              ? item.productCode! 
              : 'PROD-${item.productId}';
          
          final nameSnapshot = item.productName.isNotEmpty 
              ? item.productName 
              : 'Producto Desconocido';
          
          debugPrint('  → Item: $codeSnapshot | $nameSnapshot | qty=${item.qty}');
          
          await txn.insert(DbTables.posTicketItems, {
            'ticket_id': ticketId,
            'product_id': item.productId,
            'product_code_snapshot': codeSnapshot,
            'product_name_snapshot': nameSnapshot,
            'description': item.description,
            'qty': item.qty,
            'price': item.price,
            'cost': item.cost,
            'discount_line': item.discountLine,
            'total_line': item.totalLine,
          });
          itemsInserted++;
        }
        debugPrint('✅ [CONVERTER] $itemsInserted items insertados');
        
        // 6. ACTUALIZAR ESTADO de cotización
        debugPrint('📝 [CONVERTER] Paso 6: Actualizando estado de cotización');
        await txn.update(
          DbTables.quotes,
          {
            'status': 'PASSED_TO_TICKET',
            'updated_at_ms': nowMs,
          },
          where: 'id = ?',
          whereArgs: [quoteId],
        );
        debugPrint('✅ [CONVERTER] Estado de cotización actualizado a PASSED_TO_TICKET');
        
        // 7. SUCCESS
        debugPrint('🎉 [CONVERTER] Conversión exitosa: Cotización #$quoteId → Ticket #$ticketId');
        return ticketId;
        
      } catch (e, stackTrace) {
        debugPrint('❌ [CONVERTER] ERROR en conversión: $e');
        debugPrint('Stack trace: $stackTrace');
        rethrow; // La transacción se revierte automáticamente
      }
    });
  }
}
