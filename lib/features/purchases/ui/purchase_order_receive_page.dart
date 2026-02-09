import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/errors/error_handler.dart';
import '../data/purchases_repository.dart';
import '../data/purchase_order_models.dart';
import '../utils/purchase_order_pdf_launcher.dart';

class PurchaseOrderReceivePage extends StatefulWidget {
  final int orderId;

  const PurchaseOrderReceivePage({super.key, required this.orderId});

  @override
  State<PurchaseOrderReceivePage> createState() =>
      _PurchaseOrderReceivePageState();
}

class _PurchaseOrderReceivePageState extends State<PurchaseOrderReceivePage> {
  final PurchasesRepository _repo = PurchasesRepository();

  bool _loading = true;
  bool _receiving = false;
  String? _error;
  PurchaseOrderDetailDto? _detail;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final detail = await _repo.getOrderById(widget.orderId);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _receive() async {
    final detail = _detail;
    if (detail == null) return;

    final isReceived = detail.order.status.toUpperCase() == 'RECIBIDA';
    if (isReceived) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) {
        return AlertDialog(
          title: const Text('Recibir orden'),
          content: const Text(
            'Al recibir la orden se actualizará el inventario (entrada de stock). ¿Continuar?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(c).pop(false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(c).pop(true),
              child: const Text('Recibir'),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;
    if (!mounted) return;

    setState(() => _receiving = true);
    try {
      await _repo.markAsReceived(widget.orderId);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Orden recibida e inventario actualizado'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e, st) {
      if (!mounted) return;
      await ErrorHandler.instance.handle(
        e,
        stackTrace: st,
        context: context,
        onRetry: _receive,
        module: 'purchases/receive',
      );
    } finally {
      if (mounted) setState(() => _receiving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat('#,##0.00', 'en_US');
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');

    final detail = _detail;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text(
          'Recibir Orden',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        toolbarHeight: 48,
        actions: [
          TextButton(
            onPressed: () => context.go('/purchases'),
            child: const Text('Volver'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Text(
                'Error: $_error',
                style: const TextStyle(color: Colors.red),
              ),
            )
          : detail == null
          ? Center(
              child: Text(
                'Orden no encontrada',
                style: TextStyle(color: AppColors.textDarkSecondary),
              ),
            )
          : Padding(
              padding: const EdgeInsets.all(AppSizes.paddingL),
              child: Column(
                children: [
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: AppColors.surfaceLightBorder),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(AppSizes.paddingM),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Orden #${detail.order.id ?? '-'}',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Suplidor: ${detail.supplierName}',
                                  style: TextStyle(
                                    color: AppColors.textDarkSecondary,
                                  ),
                                ),
                                Text(
                                  'Fecha: ${dateFormat.format(DateTime.fromMillisecondsSinceEpoch(detail.order.createdAtMs))}',
                                  style: TextStyle(
                                    color: AppColors.textDarkSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          OutlinedButton.icon(
                            onPressed: () =>
                                PurchaseOrderPdfLauncher.openPreviewDialog(
                                  context: context,
                                  detail: detail,
                                ),
                            icon: const Icon(Icons.picture_as_pdf),
                            label: const Text(
                              'Enviar por WhatsApp / Descargar PDF',
                            ),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton.icon(
                            onPressed:
                                _receiving ||
                                    detail.order.status.toUpperCase() ==
                                        'RECIBIDA'
                                ? null
                                : _receive,
                            icon: _receiving
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.check_circle_outline),
                            label: Text(
                              detail.order.status.toUpperCase() == 'RECIBIDA'
                                  ? 'Recibida'
                                  : 'Recibir',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSizes.paddingM),
                  Expanded(
                    child: Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: AppColors.surfaceLightBorder),
                      ),
                      child: ListView.separated(
                        itemCount: detail.items.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final it = detail.items[index];
                          return ListTile(
                            title: Text(
                              '${it.productCode} • ${it.productName}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              'Cant: ${it.item.qty.toStringAsFixed(2)} • Costo: ${currency.format(it.item.unitCost)}',
                            ),
                            trailing: Text(
                              currency.format(it.item.totalLine),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSizes.paddingM),
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: AppColors.surfaceLightBorder),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(AppSizes.paddingM),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            'Subtotal: ${currency.format(detail.order.subtotal)}   ',
                          ),
                          Text(
                            'Impuesto: ${currency.format(detail.order.taxAmount)}   ',
                          ),
                          Text(
                            'Total: ${currency.format(detail.order.total)}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
