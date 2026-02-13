import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../data/credits_repository.dart';
import '../data/layaway_repository.dart';
import '../data/sales_repository.dart';
import '../../../core/db_hardening/db_hardening.dart';
import '../../../core/errors/error_handler.dart';
import '../../../core/printing/unified_ticket_printer.dart';
import '../../../core/session/session_manager.dart';
import '../../settings/data/printer_settings_repository.dart';
import '../../cash/data/cash_repository.dart' as cash_repo;
import '../../../core/theme/app_status_theme.dart';
import '../../../core/ui/dialog_keyboard_shortcuts.dart';

class CreditsPage extends StatefulWidget {
  const CreditsPage({super.key});

  @override
  State<CreditsPage> createState() => _CreditsPageState();
}

class _CreditsPageState extends State<CreditsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _loading = true;
  List<Map<String, dynamic>> _creditsByClient = [];
  List<Map<String, dynamic>> _creditSales = [];
  List<Map<String, dynamic>> _layawaySales = [];
  String? _selectedClientName;
  int? _selectedCreditId;
  int? _selectedLayawayId;
  int _loadSeq = 0;

  late final TextEditingController _byClientSearchController;
  late final TextEditingController _creditSearchController;
  late final TextEditingController _layawaySearchController;

  static const _brandDark = Colors.black;
  static const _brandLight = Colors.white;
  static const _controlRadius = 10.0;
  static const bool _isFlutterTest = bool.fromEnvironment('FLUTTER_TEST');

  ThemeData get _theme => Theme.of(context);
  ColorScheme get _scheme => _theme.colorScheme;
  AppStatusTheme get _status =>
      _theme.extension<AppStatusTheme>() ??
      AppStatusTheme(
        success: _scheme.primary,
        warning: _scheme.tertiary,
        error: _scheme.error,
        info: _scheme.secondary,
      );
  NumberFormat get _currency =>
      NumberFormat.currency(locale: 'es_DO', symbol: 'RD\$');

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _byClientSearchController = TextEditingController();
    _creditSearchController = TextEditingController();
    _layawaySearchController = TextEditingController();
    Future.delayed(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route != null && !route.isCurrent) return;
      _loadCredits();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _byClientSearchController.dispose();
    _creditSearchController.dispose();
    _layawaySearchController.dispose();
    super.dispose();
  }

  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  Future<void> _loadCredits() async {
    final seq = ++_loadSeq;
    _safeSetState(() => _loading = true);
    try {
      final results = await DbHardening.instance.runDbSafe<List<dynamic>>(
        () async {
          final byClient = await CreditsRepository.getCreditSummaryByClient();
          final sales = await CreditsRepository.listCreditSales();
          final layaways = await LayawayRepository.listLayawaySales();
          return [byClient, sales, layaways];
        },
        stage: 'sales/credits/load',
      );
      final byClient = results[0] as List<Map<String, dynamic>>;
      final sales = results[1] as List<Map<String, dynamic>>;
      final layaways = results[2] as List<Map<String, dynamic>>;

      if (!mounted || seq != _loadSeq) return;
      _safeSetState(() {
        _creditsByClient = byClient;
        _creditSales = sales;
        _layawaySales = layaways;

        if (_creditsByClient.isNotEmpty) {
          final match = _selectedClientName != null
              ? _creditsByClient.firstWhere(
                  (c) => (c['nombre'] ?? '').toString() == _selectedClientName,
                  orElse: () => _creditsByClient.first,
                )
              : _creditsByClient.first;
          _selectedClientName = (match['nombre'] ?? '').toString();
        } else {
          _selectedClientName = null;
        }

        if (_creditSales.isNotEmpty) {
          final match = _selectedCreditId != null
              ? _creditSales.firstWhere(
                  (sale) => sale['id'] == _selectedCreditId,
                  orElse: () => _creditSales.first,
                )
              : _creditSales.first;
          _selectedCreditId = match['id'] as int?;
        } else {
          _selectedCreditId = null;
        }
        if (_layawaySales.isNotEmpty) {
          final match = _selectedLayawayId != null
              ? _layawaySales.firstWhere(
                  (sale) => sale['id'] == _selectedLayawayId,
                  orElse: () => _layawaySales.first,
                )
              : _layawaySales.first;
          _selectedLayawayId = match['id'] as int?;
        } else {
          _selectedLayawayId = null;
        }
      });
    } catch (e, st) {
      if (!mounted) return;
      await ErrorHandler.instance.handle(
        e,
        stackTrace: st,
        context: context,
        onRetry: _loadCredits,
        module: 'sales/credits/load',
      );
    } finally {
      if (mounted && seq == _loadSeq) {
        _safeSetState(() => _loading = false);
      }
    }
  }

  EdgeInsets _pagePadding(BoxConstraints constraints) {
    final horizontal = (constraints.maxWidth * 0.02).clamp(12.0, 20.0);
    final vertical = (constraints.maxHeight * 0.02).clamp(10.0, 18.0);
    return EdgeInsets.symmetric(horizontal: horizontal, vertical: vertical);
  }

  String _formatCurrency(double value) => _currency.format(value);

  String _formatDate(int? ms) {
    if (ms == null) return 'Sin fecha';
    return DateFormat(
      'dd/MM/yyyy',
    ).format(DateTime.fromMillisecondsSinceEpoch(ms));
  }

  Widget _loadingIndicator() {
    if (_isFlutterTest) {
      return const CircularProgressIndicator(value: 0.2);
    }
    return const CircularProgressIndicator();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 0,
        titleSpacing: 0,
        automaticallyImplyLeading: false,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Por Cliente'),
            Tab(text: 'Ventas a Crédito'),
            Tab(text: 'Apartados'),
          ],
        ),
      ),
      body: _loading
          ? Center(child: _loadingIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                // Tab 1: Por Cliente
                _buildByClientTab(),
                // Tab 2: Ventas a Crédito
                _buildCreditSalesTab(),
                // Tab 3: Apartados
                _buildLayawayTab(),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _loadCredits,
        child: const Icon(Icons.refresh),
      ),
    );
  }

  Map<String, dynamic>? _findSelectedByStringKey(
    List<Map<String, dynamic>> items,
    String? selected,
    String key,
  ) {
    if (selected == null) return null;
    for (final item in items) {
      if ((item[key] ?? '').toString() == selected) return item;
    }
    return null;
  }

  Map<String, dynamic>? _findSelectedById(
    List<Map<String, dynamic>> items,
    int? selectedId,
  ) {
    if (selectedId == null) return null;
    for (final item in items) {
      if (item['id'] == selectedId) return item;
    }
    return null;
  }

  List<Map<String, dynamic>> _filterByQuery(
    List<Map<String, dynamic>> items,
    String query,
    List<String> keys,
  ) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return items;
    return items.where((item) {
      for (final k in keys) {
        final v = (item[k] ?? '').toString().toLowerCase();
        if (v.contains(q)) return true;
      }
      return false;
    }).toList();
  }

  Widget _buildSectionHeader({
    required TextEditingController controller,
    required String hint,
    required Widget summary,
  }) {
    final scheme = _scheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final padding = _pagePadding(constraints);
        final isNarrow = constraints.maxWidth < 980;
        final baseBorder = OutlineInputBorder(
          borderRadius: BorderRadius.circular(_controlRadius),
          borderSide: BorderSide(color: scheme.outlineVariant),
        );
        final searchField = TextField(
          controller: controller,
          style: const TextStyle(color: _brandLight),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: _brandLight.withOpacity(0.70)),
            filled: true,
            fillColor: _brandDark,
            prefixIcon: Icon(
              Icons.search,
              color: _brandLight.withOpacity(0.85),
            ),
            suffixIcon: controller.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    color: _brandLight.withOpacity(0.90),
                    onPressed: () {
                      _safeSetState(() {
                        controller.clear();
                      });
                    },
                  )
                : null,
            border: baseBorder,
            enabledBorder: baseBorder,
            focusedBorder: baseBorder.copyWith(
              borderSide: BorderSide(color: scheme.primary),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
          ),
          onChanged: (_) {
            _safeSetState(() {});
          },
        );

        return Container(
          color: scheme.surfaceContainerHighest,
          padding: EdgeInsets.fromLTRB(
            padding.left,
            (padding.top * 0.8).clamp(8.0, 14.0),
            padding.right,
            (padding.top * 0.8).clamp(8.0, 14.0),
          ),
          child: isNarrow
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [searchField, const SizedBox(height: 8), summary],
                )
              : Row(
                  children: [
                    Expanded(flex: 4, child: searchField),
                    const SizedBox(width: 10),
                    summary,
                  ],
                ),
        );
      },
    );
  }

  Widget _buildSummaryChip({
    required IconData icon,
    required String left,
    required String right,
  }) {
    final scheme = _scheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: _brandDark,
        borderRadius: BorderRadius.circular(_controlRadius),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: _brandLight.withOpacity(0.85)),
          const SizedBox(width: 8),
          Text(
            left,
            style: _theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: _brandLight,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            right,
            style: _theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: _brandLight,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildByClientTab() {
    if (_creditsByClient.isEmpty) {
      return const Center(child: Text('No hay créditos'));
    }

    final scheme = _scheme;
    final status = _status;
    final filtered = _filterByQuery(
      _creditsByClient,
      _byClientSearchController.text,
      const ['nombre'],
    );
    final selected = _findSelectedByStringKey(
      filtered,
      _selectedClientName,
      'nombre',
    );
    final sumPending = filtered.fold<double>(
      0,
      (sum, c) => sum + ((c['total_pending'] as num?)?.toDouble() ?? 0.0),
    );

    return Column(
      children: [
        _buildSectionHeader(
          controller: _byClientSearchController,
          hint: 'Buscar cliente...',
          summary: _buildSummaryChip(
            icon: Icons.people_alt_outlined,
            left: 'Clientes: ${filtered.length}',
            right: 'Pend.: ${_formatCurrency(sumPending)}',
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final padding = _pagePadding(constraints);
              final isWide = constraints.maxWidth >= 1200;
              final detailWidth = (constraints.maxWidth * 0.25).clamp(
                300.0,
                460.0,
              );

              final list = ListView.separated(
                padding: padding,
                itemCount: filtered.length,
                separatorBuilder: (_, index) => const SizedBox(height: 6),
                itemBuilder: (context, index) {
                  final item = filtered[index];
                  final clientName = (item['nombre'] ?? 'S/N').toString();
                  final totalPending =
                      (item['total_pending'] as num?)?.toDouble() ?? 0.0;
                  final totalAmount =
                      (item['total_amount'] as num?)?.toDouble() ?? 0.0;
                  final totalCredits = item['total_credits'] as int? ?? 0;
                  final chipColor = totalPending > 0
                      ? status.error
                      : status.success;
                  final isSelected =
                      _selectedClientName != null &&
                      clientName == _selectedClientName;

                  final rowColor = isSelected
                      ? scheme.primary.withOpacity(0.06)
                      : scheme.surface;

                  return Material(
                    color: rowColor,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        _safeSetState(() {
                          _selectedClientName = clientName;
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: scheme.outlineVariant),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 5,
                              child: Text(
                                clientName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: _theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: scheme.onSurface,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              flex: 2,
                              child: Text(
                                totalCredits.toString(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.right,
                                style: _theme.textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: scheme.onSurface.withOpacity(0.8),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              flex: 3,
                              child: Text(
                                _formatCurrency(totalAmount),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.right,
                                style: _theme.textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  color: scheme.onSurface,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              flex: 3,
                              child: Text(
                                _formatCurrency(totalPending),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.right,
                                style: _theme.textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  color: scheme.onSurface,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: chipColor.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: chipColor.withOpacity(0.35),
                                ),
                              ),
                              child: Text(
                                totalPending > 0 ? 'PEND.' : 'OK',
                                style: _theme.textTheme.labelSmall?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  color: scheme.onSurface,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            PopupMenuButton<String>(
                              tooltip: 'Acciones',
                              icon: Icon(
                                Icons.more_vert,
                                size: 18,
                                color: scheme.onSurface.withOpacity(0.7),
                              ),
                              onSelected: (v) {
                                if (v == 'view') {
                                  _safeSetState(() {
                                    _selectedClientName = clientName;
                                  });
                                }
                              },
                              itemBuilder: (context) => const [
                                PopupMenuItem(
                                  value: 'view',
                                  child: Text('Ver resumen'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );

              final detail = _buildClientSummaryDetailPanel(selected);

              if (isWide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: list),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: detailWidth,
                      child: SizedBox.expand(child: detail),
                    ),
                  ],
                );
              }

              return Column(
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      padding.left,
                      padding.top,
                      padding.right,
                      0,
                    ),
                    child: detail,
                  ),
                  const SizedBox(height: 12),
                  Expanded(child: list),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildClientSummaryDetailPanel(Map<String, dynamic>? summary) {
    final scheme = _scheme;
    if (summary == null) {
      return Card(
        margin: EdgeInsets.zero,
        color: scheme.surface,
        elevation: 1,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.person_outline,
                size: 40,
                color: scheme.onSurface.withOpacity(0.4),
              ),
              const SizedBox(height: 10),
              Text(
                'Selecciona un cliente para ver el resumen',
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurface.withOpacity(0.6)),
              ),
            ],
          ),
        ),
      );
    }

    final status = _status;
    final clientName = (summary['nombre'] ?? 'S/N').toString();
    final totalPending = (summary['total_pending'] as num?)?.toDouble() ?? 0.0;
    final totalAmount = (summary['total_amount'] as num?)?.toDouble() ?? 0.0;
    final totalCredits = summary['total_credits'] as int? ?? 0;
    final chipColor = totalPending > 0 ? status.error : status.success;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 2,
      color: scheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Resumen del cliente',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                clientName,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 12),
              _detailRow('Créditos', totalCredits.toString()),
              _detailRow('Total', _formatCurrency(totalAmount)),
              _detailRow('Pendiente', _formatCurrency(totalPending)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: chipColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: chipColor.withOpacity(0.35)),
                ),
                child: Text(
                  totalPending > 0 ? 'TIENE SALDO PENDIENTE' : 'AL DÍA',
                  style: _theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: scheme.onSurface,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCreditSalesTab() {
    if (_creditSales.isEmpty) {
      return const Center(child: Text('No hay ventas a crédito'));
    }

    final filtered = _filterByQuery(
      _creditSales,
      _creditSearchController.text,
      const ['local_code', 'customer_name_snapshot', 'customer_phone_snapshot'],
    );
    final selected = _findSelectedById(filtered, _selectedCreditId);
    final pendingTotal = filtered.fold<double>(
      0,
      (sum, s) => sum + ((s['amount_pending'] as num?)?.toDouble() ?? 0.0),
    );

    return Column(
      children: [
        _buildSectionHeader(
          controller: _creditSearchController,
          hint: 'Buscar por cliente, teléfono o factura...',
          summary: _buildSummaryChip(
            icon: Icons.receipt_long,
            left: 'Ventas: ${filtered.length}',
            right: 'Pend.: ${_formatCurrency(pendingTotal)}',
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final padding = _pagePadding(constraints);
              final isWide = constraints.maxWidth >= 1200;
              final detailWidth = (constraints.maxWidth * 0.25).clamp(
                300.0,
                460.0,
              );

              final list = ListView.separated(
                padding: padding,
                itemCount: filtered.length,
                separatorBuilder: (_, index) => const SizedBox(height: 6),
                itemBuilder: (context, index) {
                  final sale = filtered[index];
                  final isSelected = sale['id'] == _selectedCreditId;
                  return _buildCreditRow(sale, isSelected);
                },
              );

              final detail = _buildCreditDetailPanel(selected);

              if (isWide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: list),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: detailWidth,
                      child: SizedBox.expand(child: detail),
                    ),
                  ],
                );
              }

              return Column(
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      padding.left,
                      padding.top,
                      padding.right,
                      0,
                    ),
                    child: detail,
                  ),
                  const SizedBox(height: 12),
                  Expanded(child: list),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildLayawayTab() {
    if (_layawaySales.isEmpty) {
      return const Center(child: Text('No hay apartados'));
    }

    final filtered = _filterByQuery(
      _layawaySales,
      _layawaySearchController.text,
      const ['local_code', 'customer_name_snapshot', 'customer_phone_snapshot'],
    );
    final selected = _findSelectedById(filtered, _selectedLayawayId);
    final pendingTotal = filtered.fold<double>(
      0,
      (sum, s) => sum + ((s['amount_pending'] as num?)?.toDouble() ?? 0.0),
    );

    return Column(
      children: [
        _buildSectionHeader(
          controller: _layawaySearchController,
          hint: 'Buscar por cliente, teléfono o factura...',
          summary: _buildSummaryChip(
            icon: Icons.bookmark,
            left: 'Apartados: ${filtered.length}',
            right: 'Pend.: ${_formatCurrency(pendingTotal)}',
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final padding = _pagePadding(constraints);
              final isWide = constraints.maxWidth >= 1200;
              final detailWidth = (constraints.maxWidth * 0.25).clamp(
                300.0,
                460.0,
              );

              final list = ListView.separated(
                padding: padding,
                itemCount: filtered.length,
                separatorBuilder: (_, index) => const SizedBox(height: 6),
                itemBuilder: (context, index) {
                  final sale = filtered[index];
                  final isSelected = sale['id'] == _selectedLayawayId;
                  return _buildLayawayRow(sale, isSelected);
                },
              );

              final detail = _buildLayawayDetailPanel(selected);

              if (isWide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: list),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: detailWidth,
                      child: SizedBox.expand(child: detail),
                    ),
                  ],
                );
              }

              return Column(
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      padding.left,
                      padding.top,
                      padding.right,
                      0,
                    ),
                    child: detail,
                  ),
                  const SizedBox(height: 12),
                  Expanded(child: list),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildLayawayRow(Map<String, dynamic> sale, bool isSelected) {
    final localCode = sale['local_code'] ?? 'N/A';
    final clientName = sale['customer_name_snapshot'] ?? 'S/C';
    final pendingRaw = (sale['amount_pending'] as num?)?.toDouble() ?? 0.0;
    final pending = pendingRaw.clamp(0.0, double.infinity);
    final total = (sale['total'] as num?)?.toDouble() ?? 0.0;
    final statusLabel = sale['layaway_status'] ?? sale['status'] ?? 'APARTADO';
    final chipColor = statusLabel == 'PAID' ? _status.success : _status.warning;
    final rowColor = isSelected
        ? _scheme.primary.withOpacity(0.06)
        : _scheme.surface;

    return Material(
      color: rowColor,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          setState(() {
            _selectedLayawayId = sale['id'] as int?;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _scheme.outlineVariant),
          ),
          child: Row(
            children: [
              Expanded(
                flex: 2,
                child: Text(
                  localCode.toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: _scheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 5,
                child: Text(
                  clientName.toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: _scheme.onSurface.withOpacity(0.85),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 3,
                child: Text(
                  _formatCurrency(total),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: _theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: _scheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 3,
                child: Text(
                  _formatCurrency(pending),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: _theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: _scheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: chipColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: chipColor.withOpacity(0.35)),
                ),
                child: Text(
                  statusLabel.toString(),
                  style: _theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: _scheme.onSurface,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              PopupMenuButton<String>(
                tooltip: 'Acciones',
                icon: Icon(
                  Icons.more_vert,
                  size: 18,
                  color: _scheme.onSurface.withOpacity(0.7),
                ),
                onSelected: (v) {
                  if (v == 'view') {
                    _safeSetState(() {
                      _selectedLayawayId = sale['id'] as int?;
                    });
                  }
                  if (v == 'pay') {
                    final saleId = sale['id'] as int?;
                    if (saleId == null) return;
                    if (pending <= 0) return;
                    _showLayawayPaymentDialog(
                      saleId,
                      localCode.toString(),
                      clientName.toString(),
                      total,
                      pending,
                      sale['customer_id'] as int?,
                    );
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'view',
                    child: Text('Ver detalle'),
                  ),
                  PopupMenuItem(
                    value: 'pay',
                    enabled: pending > 0,
                    child: const Text('Registrar abono'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLayawayDetailPanel(Map<String, dynamic>? sale) {
    if (sale == null) {
      return Card(
        margin: EdgeInsets.zero,
        color: _scheme.surface,
        elevation: 1,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.bookmark,
                size: 40,
                color: _scheme.onSurface.withOpacity(0.4),
              ),
              const SizedBox(height: 10),
              Text(
                'Selecciona un apartado para ver el detalle',
                textAlign: TextAlign.center,
                style: TextStyle(color: _scheme.onSurface.withOpacity(0.6)),
              ),
            ],
          ),
        ),
      );
    }

    final saleId = sale['id'] as int?;
    final localCode = sale['local_code'] ?? 'N/A';
    final clientName = sale['customer_name_snapshot'] ?? 'S/C';
    final phone = sale['customer_phone_snapshot'] ?? '';
    final total = (sale['total'] as num?)?.toDouble() ?? 0.0;
    final paid = (sale['amount_paid'] as num?)?.toDouble() ?? 0.0;
    final pendingRaw = (sale['amount_pending'] as num?)?.toDouble() ?? 0.0;
    final pending = pendingRaw.clamp(0.0, double.infinity);
    final statusLabel = sale['layaway_status'] ?? sale['status'] ?? 'APARTADO';
    final isPaid = statusLabel == 'PAID' || pending <= 0;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 2,
      color: _scheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Detalle de apartado',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: _scheme.onSurface,
                ),
              ),
              const SizedBox(height: 12),
              _detailRow('Factura', localCode.toString()),
              _detailRow('Cliente', clientName.toString()),
              if (phone.toString().isNotEmpty)
                _detailRow('Telefono', phone.toString()),
              _detailRow('Total', _formatCurrency(total)),
              _detailRow('Pagado', _formatCurrency(paid)),
              _detailRow('Pendiente', _formatCurrency(pending)),
              _detailRow('Estado', isPaid ? 'Saldado' : 'Pendiente'),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: saleId == null || isPaid
                      ? null
                      : () => _showLayawayPaymentDialog(
                          saleId,
                          localCode.toString(),
                          clientName.toString(),
                          total,
                          pending,
                          sale['customer_id'] as int?,
                        ),
                  icon: const Icon(Icons.payments_outlined, size: 18),
                  label: const Text('Registrar abono'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _scheme.primary,
                    foregroundColor: _scheme.onPrimary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(_controlRadius),
                    ),
                    textStyle: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCreditRow(Map<String, dynamic> sale, bool isSelected) {
    final localCode = sale['local_code'] ?? 'N/A';
    final clientName = sale['customer_name_snapshot'] ?? 'S/C';
    final pendingRaw = (sale['amount_pending'] as num?)?.toDouble() ?? 0.0;
    final pending = pendingRaw.clamp(0.0, double.infinity);
    final totalDue =
        (sale['total_due'] as num?)?.toDouble() ??
        ((sale['total'] as num?)?.toDouble() ?? 0.0);
    final dueDateMs = sale['credit_due_date_ms'] as int?;
    final statusLabel = sale['credit_status'] ?? sale['status'] ?? 'CREDIT';
    final chipColor = statusLabel == 'PAID' ? _status.success : _status.warning;
    final rowColor = isSelected
        ? _scheme.primary.withOpacity(0.06)
        : _scheme.surface;

    return Material(
      color: rowColor,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          setState(() {
            _selectedCreditId = sale['id'] as int?;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _scheme.outlineVariant),
          ),
          child: Row(
            children: [
              Expanded(
                flex: 2,
                child: Text(
                  localCode.toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: _scheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 5,
                child: Text(
                  clientName.toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: _scheme.onSurface.withOpacity(0.85),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 3,
                child: Text(
                  _formatDate(dueDateMs),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: _scheme.onSurface.withOpacity(0.75),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 3,
                child: Text(
                  _formatCurrency(totalDue),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: _theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: _scheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 3,
                child: Text(
                  _formatCurrency(pending),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: _theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: _scheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: chipColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: chipColor.withOpacity(0.35)),
                ),
                child: Text(
                  statusLabel.toString(),
                  style: _theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: _scheme.onSurface,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              PopupMenuButton<String>(
                tooltip: 'Acciones',
                icon: Icon(
                  Icons.more_vert,
                  size: 18,
                  color: _scheme.onSurface.withOpacity(0.7),
                ),
                onSelected: (v) {
                  if (v == 'view') {
                    _safeSetState(() {
                      _selectedCreditId = sale['id'] as int?;
                    });
                  }
                  if (v == 'pay') {
                    final saleId = sale['id'] as int?;
                    if (saleId == null) return;
                    _showPaymentDialog(
                      saleId,
                      localCode.toString(),
                      clientName.toString(),
                      totalDue,
                      pending,
                      sale['customer_id'] as int?,
                    );
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'view', child: Text('Ver detalle')),
                  PopupMenuItem(value: 'pay', child: Text('Registrar abono')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCreditDetailPanel(Map<String, dynamic>? sale) {
    if (sale == null) {
      return Card(
        margin: EdgeInsets.zero,
        color: _scheme.surface,
        elevation: 1,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.receipt_long,
                size: 40,
                color: _scheme.onSurface.withOpacity(0.4),
              ),
              const SizedBox(height: 10),
              Text(
                'Selecciona un crédito para ver el detalle',
                textAlign: TextAlign.center,
                style: TextStyle(color: _scheme.onSurface.withOpacity(0.6)),
              ),
            ],
          ),
        ),
      );
    }

    final saleId = sale['id'] as int?;
    final localCode = sale['local_code'] ?? 'N/A';
    final clientName = sale['customer_name_snapshot'] ?? 'S/C';
    final phone = sale['customer_phone_snapshot'] ?? '';
    final baseTotal = (sale['total'] as num?)?.toDouble() ?? 0.0;
    final interestRate =
        (sale['credit_interest_rate'] as num?)?.toDouble() ?? 0.0;
    final totalDue = (sale['total_due'] as num?)?.toDouble() ?? baseTotal;
    final pendingRaw = (sale['amount_pending'] as num?)?.toDouble() ?? 0.0;
    final pending = pendingRaw.clamp(0.0, double.infinity);
    final paid = (sale['amount_paid'] as num?)?.toDouble() ?? 0.0;
    final termDays = sale['credit_term_days'] as int?;
    final installments = sale['credit_installments'] as int?;
    final note = (sale['credit_note'] as String?) ?? '';
    final dueDateMs = sale['credit_due_date_ms'] as int?;
    final installmentAmount = (installments != null && installments > 0)
        ? totalDue / installments
        : null;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 2,
      color: _scheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Detalle de crédito',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: _scheme.onSurface,
                ),
              ),
              const SizedBox(height: 12),
              _detailRow('Factura', localCode.toString()),
              _detailRow('Cliente', clientName.toString()),
              if (phone.toString().isNotEmpty)
                _detailRow('Telefono', phone.toString()),
              _detailRow('Total venta', _formatCurrency(baseTotal)),
              _detailRow('Interes', '${interestRate.toStringAsFixed(2)}%'),
              _detailRow('Total credito', _formatCurrency(totalDue)),
              _detailRow('Pagado', _formatCurrency(paid)),
              _detailRow('Pendiente', _formatCurrency(pending)),
              if (termDays != null && termDays > 0)
                _detailRow('Plazo (dias)', termDays.toString()),
              if (installments != null && installments > 0)
                _detailRow('Cuotas', installments.toString()),
              if (installmentAmount != null)
                _detailRow('Valor cuota', _formatCurrency(installmentAmount)),
              if (dueDateMs != null)
                _detailRow('Vence', _formatDate(dueDateMs)),
              if (note.trim().isNotEmpty) _detailRow('Nota', note),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: saleId == null
                      ? null
                      : () => _showPaymentDialog(
                          saleId,
                          localCode.toString(),
                          clientName.toString(),
                          totalDue,
                          pending,
                          sale['customer_id'] as int?,
                        ),
                  icon: const Icon(Icons.payments_outlined, size: 18),
                  label: const Text('Registrar abono'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _scheme.primary,
                    foregroundColor: _scheme.onPrimary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(_controlRadius),
                    ),
                    textStyle: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Text(
              label,
              style: TextStyle(
                color: _scheme.onSurface.withOpacity(0.7),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            flex: 6,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: _scheme.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showPaymentDialog(
    int saleId,
    String saleCode,
    String clientName,
    double saleTotal,
    double pendingAmount,
    int? clientId,
  ) {
    final amountController = TextEditingController();

    Future<void> submit(BuildContext dialogContext) async {
      final amount = double.tryParse(amountController.text) ?? 0.0;
      if (amount <= 0) {
        ScaffoldMessenger.of(
          dialogContext,
        ).showSnackBar(const SnackBar(content: Text('Monto inválido')));
        return;
      }
      if (pendingAmount > 0 && amount > pendingAmount) {
        ScaffoldMessenger.of(dialogContext).showSnackBar(
          SnackBar(content: Text('El abono excede el saldo pendiente')),
        );
        return;
      }

      try {
        final sessionId = await cash_repo.CashRepository.getCurrentSessionId();

        final paymentResult = await CreditsRepository.registerCreditPayment(
          saleId: saleId,
          clientId: clientId ?? 0,
          amount: amount,
          method: 'cash',
          sessionId: sessionId,
        );

        try {
          final sale = await SalesRepository.getSaleById(saleId);
          final items = await SalesRepository.getItemsBySaleId(saleId);
          if (sale != null) {
            final settings = await PrinterSettingsRepository.getOrCreate();
            if (settings.selectedPrinterName != null &&
                settings.selectedPrinterName!.isNotEmpty) {
              final cashierName =
                  await SessionManager.displayName() ?? 'Cajero';
              final pendingAfter = paymentResult.pendingAmount;
              final statusLabel = pendingAfter > 0 ? 'PENDIENTE' : 'PAGADO';
              final saleForPrint = sale.copyWith(
                paidAmount: paymentResult.totalPaid,
                changeAmount: 0.0,
              );

              await UnifiedTicketPrinter.printSaleTicket(
                sale: saleForPrint,
                items: items,
                cashierName: cashierName,
                pendingAmount: pendingAfter,
                lastPaymentAmount: amount,
                statusLabel: statusLabel,
              );
            }
          }
        } catch (e) {
          debugPrint('Error al imprimir ticket de crédito: $e');
        }

        if (dialogContext.mounted) {
          Navigator.pop(dialogContext);
        }

        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Abono registrado')));
          _loadCredits();
        }
      } catch (e, st) {
        if (mounted) {
          await ErrorHandler.instance.handle(
            e,
            stackTrace: st,
            context: context,
            onRetry: () => _showPaymentDialog(
              saleId,
              saleCode,
              clientName,
              saleTotal,
              pendingAmount,
              clientId,
            ),
            module: 'sales/credits/payment',
          );
        }
      }
    }

    showDialog(
      context: context,
      builder: (dialogContext) => DialogKeyboardShortcuts(
        onSubmit: () => submit(dialogContext),
        child: Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Registrar abono',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text('Factura: $saleCode'),
                Text('Cliente: $clientName'),
                Text('Total: ${_formatCurrency(saleTotal)}'),
                Text('Pendiente: ${_formatCurrency(pendingAmount)}'),
                const SizedBox(height: 14),
                TextField(
                  controller: amountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: false,
                  ),
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => submit(dialogContext),
                  decoration: const InputDecoration(
                    labelText: 'Monto a abonar',
                    prefixText: '\$ ',
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Cancelar'),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: () => submit(dialogContext),
                      child: const Text('Registrar'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showLayawayPaymentDialog(
    int saleId,
    String saleCode,
    String clientName,
    double saleTotal,
    double pendingAmount,
    int? clientId,
  ) {
    final amountController = TextEditingController();

    Future<void> submit(BuildContext dialogContext) async {
      final amount = double.tryParse(amountController.text) ?? 0.0;
      if (amount <= 0) {
        ScaffoldMessenger.of(
          dialogContext,
        ).showSnackBar(const SnackBar(content: Text('Monto inválido')));
        return;
      }
      if (pendingAmount > 0 && amount > pendingAmount) {
        ScaffoldMessenger.of(dialogContext).showSnackBar(
          const SnackBar(content: Text('El abono excede el saldo pendiente')),
        );
        return;
      }

      try {
        final sessionId = await cash_repo.CashRepository.getCurrentSessionId();
        if (sessionId == null) {
          ScaffoldMessenger.of(dialogContext).showSnackBar(
            const SnackBar(
              content: Text(
                'Debe abrir caja para registrar abonos de apartado',
              ),
            ),
          );
          return;
        }
        final paymentResult = await LayawayRepository.registerLayawayPayment(
          saleId: saleId,
          clientId: clientId,
          amount: amount,
          method: 'cash',
          sessionId: sessionId,
        );

        try {
          final sale = await SalesRepository.getSaleById(saleId);
          final items = await SalesRepository.getItemsBySaleId(saleId);
          if (sale != null) {
            final settings = await PrinterSettingsRepository.getOrCreate();
            if (settings.selectedPrinterName != null &&
                settings.selectedPrinterName!.isNotEmpty) {
              final cashierName =
                  await SessionManager.displayName() ?? 'Cajero';
              final pendingAfter = paymentResult.pendingAmount;
              final layawayStatusLabel = pendingAfter > 0
                  ? 'PENDIENTE'
                  : 'PAGADO';
              await UnifiedTicketPrinter.printSaleTicket(
                sale: sale,
                items: items,
                cashierName: cashierName,
                isLayaway: true,
                pendingAmount: pendingAfter,
                lastPaymentAmount: amount,
                statusLabel: layawayStatusLabel,
              );
            }
          }
        } catch (e) {
          debugPrint('Error al imprimir ticket de apartado: $e');
        }

        if (dialogContext.mounted) {
          Navigator.pop(dialogContext);
        }

        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Abono registrado')));
          _loadCredits();
        }
      } catch (e, st) {
        if (mounted) {
          await ErrorHandler.instance.handle(
            e,
            stackTrace: st,
            context: context,
            onRetry: () => _showLayawayPaymentDialog(
              saleId,
              saleCode,
              clientName,
              saleTotal,
              pendingAmount,
              clientId,
            ),
            module: 'sales/layaway/payment',
          );
        }
      }
    }

    showDialog(
      context: context,
      builder: (dialogContext) => DialogKeyboardShortcuts(
        onSubmit: () => submit(dialogContext),
        child: Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Registrar abono',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text('Factura: $saleCode'),
                Text('Cliente: $clientName'),
                Text('Total: ${_formatCurrency(saleTotal)}'),
                Text('Pendiente: ${_formatCurrency(pendingAmount)}'),
                const SizedBox(height: 14),
                TextField(
                  controller: amountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: false,
                  ),
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => submit(dialogContext),
                  decoration: const InputDecoration(
                    labelText: 'Monto a abonar',
                    prefixText: '\$ ',
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Cancelar'),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: () => submit(dialogContext),
                      child: const Text('Registrar'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
