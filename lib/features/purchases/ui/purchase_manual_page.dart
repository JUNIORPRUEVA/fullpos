import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_sizes.dart';
import '../../settings/data/business_settings_repository.dart';
import '../providers/purchase_draft_provider.dart';
import 'widgets/purchase_header_row.dart';
import 'widgets/purchase_products_grid.dart';
import 'widgets/purchase_ticket_panel.dart';

class PurchaseManualPage extends ConsumerStatefulWidget {
  const PurchaseManualPage({super.key});

  @override
  ConsumerState<PurchaseManualPage> createState() => _PurchaseManualPageState();
}

class _PurchaseManualPageState extends ConsumerState<PurchaseManualPage> {
  final FocusNode _searchFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _loadDefaultTax();
  }

  Future<void> _loadDefaultTax() async {
    // Mantener consistente con pages legacy.
    final repo = BusinessSettingsRepository();
    final tax = await repo.getDefaultTaxRate();
    if (!mounted) return;
    ref.read(purchaseDraftProvider.notifier).setTaxRatePercent(tax);
  }

  @override
  void dispose() {
    _searchFocus.dispose();
    super.dispose();
  }

  Future<bool> _confirmExitIfDirty(BuildContext context) async {
    final draft = ref.read(purchaseDraftProvider);
    if (!draft.hasChanges) return true;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) {
        return AlertDialog(
          title: const Text('Salir sin guardar'),
          content: const Text(
            'Hay una orden en borrador. ¿Deseas salir y perder los cambios?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(c).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(c).pop(true),
              child: const Text('Salir'),
            ),
          ],
        );
      },
    );

    return confirm == true;
  }

  BoxConstraints _ticketPanelConstraints(double width) {
    if (width < 1350) {
      final max = (width * 0.34).clamp(320.0, 420.0);
      final min = (max - 70).clamp(300.0, max);
      return BoxConstraints(minWidth: min, maxWidth: max);
    }
    if (width < 1600) {
      final max = (width * 0.32).clamp(420.0, 520.0);
      final min = (max - 80).clamp(360.0, max);
      return BoxConstraints(minWidth: min, maxWidth: max);
    }
    final max = (width * 0.30).clamp(460.0, 580.0);
    final min = (max - 90).clamp(380.0, max);
    return BoxConstraints(minWidth: min, maxWidth: max);
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () => _confirmExitIfDirty(context),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text(
            'Compra Manual',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          toolbarHeight: 48,
          actions: [
            TextButton(
              onPressed: () async {
                final ok = await _confirmExitIfDirty(context);
                if (!ok) return;
                if (!context.mounted) return;
                context.go('/purchases');
              },
              child: const Text('Volver'),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(AppSizes.paddingL),
          child: Column(
            children: [
              PurchaseHeaderRow(searchFocusNode: _searchFocus),
              const SizedBox(height: 12),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    final isNarrow = width < 980;

                    final ticket = ConstrainedBox(
                      constraints: _ticketPanelConstraints(width),
                      child: PurchaseTicketPanel(
                        onOrderCreated: () => context.go('/purchases/orders'),
                      ),
                    );

                    final catalog = Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(AppSizes.radiusXL),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: const PurchaseProductsGrid(),
                    );

                    if (isNarrow) {
                      return Column(
                        children: [
                          Expanded(child: catalog),
                          const SizedBox(height: 12),
                          SizedBox(height: 520, child: ticket),
                        ],
                      );
                    }

                    return Row(
                      children: [
                        Expanded(flex: 7, child: catalog),
                        const SizedBox(width: 12),
                        Expanded(flex: 3, child: ticket),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
