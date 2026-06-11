import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/error_handler.dart';
import '../../products/data/suppliers_repository.dart';
import '../../products/models/supplier_model.dart';

class SupplierRegistrationPage extends StatefulWidget {
  const SupplierRegistrationPage({super.key});

  @override
  State<SupplierRegistrationPage> createState() =>
      _SupplierRegistrationPageState();
}

class _SupplierRegistrationPageState extends State<SupplierRegistrationPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _noteController = TextEditingController();
  final SuppliersRepository _repo = SuppliersRepository();
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  EdgeInsets _contentPadding(BoxConstraints constraints) {
    const maxContentWidth = 1280.0;
    final contentWidth = math.min(constraints.maxWidth * 0.92, maxContentWidth);
    final side = ((constraints.maxWidth - contentWidth) / 2)
        .clamp(24.0, 160.0)
        .toDouble();
    return EdgeInsets.fromLTRB(side, 22, side, 24);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      final name = _nameController.text.trim();
      if (await _repo.existsByName(name)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ya existe un suplidor con ese nombre')),
        );
        setState(() => _saving = false);
        return;
      }

      await _repo.create(
        SupplierModel(
          name: name,
          phone: _phoneController.text.trim().isEmpty
              ? null
              : _phoneController.text.trim(),
          note: _noteController.text.trim().isEmpty
              ? null
              : _noteController.text.trim(),
          createdAtMs: DateTime.now().millisecondsSinceEpoch,
          updatedAtMs: DateTime.now().millisecondsSinceEpoch,
        ),
      );

      if (!mounted) return;
      _formKey.currentState?.reset();
      _nameController.clear();
      _phoneController.clear();
      _noteController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Suplidor registrado correctamente')),
      );
    } catch (e, st) {
      if (!mounted) return;
      await ErrorHandler.instance.handle(
        e,
        stackTrace: st,
        context: context,
        onRetry: _save,
        module: 'suppliers/create_page',
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final padding = _contentPadding(constraints);
        return Container(
          color: scheme.surface,
          child: SingleChildScrollView(
            padding: padding,
            child: Column(
              children: [
                const _ModuleHeroCard(
                  eyebrow: 'Gestión',
                  title: 'Registrar suplidor',
                  subtitle:
                      'Crea suplidores en una pantalla simple, elegante y lista para usarse en compras.',
                ),
                const SizedBox(height: 18),
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxWidth: 920),
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: scheme.outlineVariant.withOpacity(0.9),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Datos del suplidor',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Completa la información base para dejar el suplidor listo para futuras compras.',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: scheme.onSurface.withOpacity(0.65),
                                ),
                          ),
                          const SizedBox(height: 20),
                          TextFormField(
                            controller: _nameController,
                            decoration: const InputDecoration(
                              labelText: 'Nombre del suplidor *',
                            ),
                            autofocus: true,
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'El nombre es obligatorio';
                              }
                              if (value.trim().length < 2) {
                                return 'Mínimo 2 caracteres';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _phoneController,
                            decoration: const InputDecoration(
                              labelText: 'Teléfono',
                            ),
                            keyboardType: TextInputType.phone,
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _noteController,
                            decoration: const InputDecoration(
                              labelText: 'Notas',
                              alignLabelWithHint: true,
                            ),
                            maxLines: 4,
                          ),
                          const SizedBox(height: 24),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                onPressed: _saving
                                    ? null
                                    : () {
                                        _formKey.currentState?.reset();
                                        _nameController.clear();
                                        _phoneController.clear();
                                        _noteController.clear();
                                      },
                                child: const Text('Limpiar'),
                              ),
                              const SizedBox(width: 10),
                              FilledButton.icon(
                                onPressed: _saving ? null : _save,
                                icon: _saving
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.save_outlined),
                                label: Text(
                                  _saving
                                      ? 'Guardando...'
                                      : 'Guardar suplidor',
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class SuppliersListPage extends StatefulWidget {
  const SuppliersListPage({super.key});

  @override
  State<SuppliersListPage> createState() => _SuppliersListPageState();
}

class _SuppliersListPageState extends State<SuppliersListPage> {
  final SuppliersRepository _repo = SuppliersRepository();
  final TextEditingController _searchController = TextEditingController();
  final DateFormat _dateFormat = DateFormat('dd/MM/yyyy');

  List<SupplierModel> _suppliers = const [];
  bool _loading = true;
  SupplierModel? _selected;
  bool _includeInactive = true;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  EdgeInsets _contentPadding(BoxConstraints constraints) {
    const maxContentWidth = 1360.0;
    final contentWidth = math.min(constraints.maxWidth * 0.92, maxContentWidth);
    final side = ((constraints.maxWidth - contentWidth) / 2)
        .clamp(24.0, 160.0)
        .toDouble();
    return EdgeInsets.fromLTRB(side, 22, side, 24);
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final suppliers = await _repo.getAll(includeInactive: _includeInactive);
      if (!mounted) return;
      setState(() {
        _suppliers = suppliers;
        _selected = suppliers.isEmpty
            ? null
            : (_selected != null
                  ? suppliers.firstWhere(
                      (item) => item.id == _selected!.id,
                      orElse: () => suppliers.first,
                    )
                  : suppliers.first);
        _loading = false;
      });
    } catch (e, st) {
      if (!mounted) return;
      setState(() => _loading = false);
      await ErrorHandler.instance.handle(
        e,
        stackTrace: st,
        context: context,
        onRetry: _load,
        module: 'suppliers/list_page',
      );
    }
  }

  List<SupplierModel> get _filtered {
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) return _suppliers;
    return _suppliers.where((supplier) {
      return supplier.name.toLowerCase().contains(q) ||
          (supplier.phone?.toLowerCase().contains(q) ?? false);
    }).toList();
  }

  Future<void> _toggleActive(SupplierModel supplier) async {
    try {
      await _repo.toggleActive(supplier.id!, !supplier.isActive);
      await _load();
    } catch (e, st) {
      if (!mounted) return;
      await ErrorHandler.instance.handle(
        e,
        stackTrace: st,
        context: context,
        onRetry: () => _toggleActive(supplier),
        module: 'suppliers/toggle_active',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final filtered = _filtered;
    return LayoutBuilder(
      builder: (context, constraints) {
        final padding = _contentPadding(constraints);
        final isWide = constraints.maxWidth >= 1180;

        final listCard = Container(
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: scheme.outlineVariant.withOpacity(0.9)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        decoration: const InputDecoration(
                          hintText: 'Buscar por nombre o teléfono...',
                          prefixIcon: Icon(Icons.search_rounded),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 170,
                      child: DropdownButtonFormField<bool>(
                        value: _includeInactive,
                        decoration: const InputDecoration(labelText: 'Vista'),
                        items: const [
                          DropdownMenuItem(value: true, child: Text('Todos')),
                          DropdownMenuItem(
                            value: false,
                            child: Text('Solo activos'),
                          ),
                        ],
                        onChanged: (value) async {
                          if (value == null) return;
                          setState(() => _includeInactive = value);
                          await _load();
                        },
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: scheme.outlineVariant.withOpacity(0.75)),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : filtered.isEmpty
                    ? const _EmptyStateCard(
                        icon: Icons.local_shipping_outlined,
                        title: 'No hay suplidores para mostrar',
                        message:
                            'Cuando registres suplidores aparecerán en esta lista.',
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(14, 14, 14, 18),
                        itemCount: filtered.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final supplier = filtered[index];
                          final isSelected = supplier.id == _selected?.id;
                          return Material(
                            color: isSelected
                                ? scheme.primary.withOpacity(0.06)
                                : scheme.surface,
                            borderRadius: BorderRadius.circular(16),
                            child: InkWell(
                              onTap: () => setState(() => _selected = supplier),
                              borderRadius: BorderRadius.circular(16),
                              child: Container(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  14,
                                  12,
                                  14,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: isSelected
                                        ? scheme.primary.withOpacity(0.35)
                                        : scheme.outlineVariant.withOpacity(0.7),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 42,
                                      height: 42,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFEAF2FF),
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: const Icon(
                                        Icons.business_rounded,
                                        color: Color(0xFF1A56DB),
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            supplier.name,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleMedium
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w800,
                                                ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            supplier.phone?.trim().isNotEmpty ==
                                                    true
                                                ? supplier.phone!
                                                : 'Sin teléfono registrado',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodyMedium
                                                ?.copyWith(
                                                  color: scheme.onSurface
                                                      .withOpacity(0.62),
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    _SupplierStatusBadge(supplier: supplier),
                                    const SizedBox(width: 8),
                                    PopupMenuButton<String>(
                                      onSelected: (value) {
                                        if (value == 'toggle') {
                                          _toggleActive(supplier);
                                        }
                                      },
                                      itemBuilder: (context) => [
                                        PopupMenuItem(
                                          value: 'toggle',
                                          child: Text(
                                            supplier.isActive
                                                ? 'Desactivar'
                                                : 'Activar',
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );

        final detailCard = _selected == null
            ? const _EmptyStateCard(
                icon: Icons.person_search_outlined,
                title: 'Selecciona un suplidor',
                message:
                    'Aquí verás sus datos principales y estado dentro del sistema.',
              )
            : Container(
                decoration: BoxDecoration(
                  color: scheme.surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: scheme.outlineVariant.withOpacity(0.9)),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _selected!.name,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 10),
                      _SupplierStatusBadge(supplier: _selected!),
                      const SizedBox(height: 18),
                      _DetailLine(
                        label: 'Teléfono',
                        value: _selected!.phone?.trim().isNotEmpty == true
                            ? _selected!.phone!
                            : 'No registrado',
                      ),
                      _DetailLine(
                        label: 'Notas',
                        value: _selected!.note?.trim().isNotEmpty == true
                            ? _selected!.note!
                            : 'Sin notas',
                      ),
                      _DetailLine(
                        label: 'Creado',
                        value: _dateFormat.format(_selected!.createdAt),
                      ),
                      _DetailLine(
                        label: 'Actualizado',
                        value: _dateFormat.format(_selected!.updatedAt),
                      ),
                    ],
                  ),
                ),
              );

        return Container(
          color: scheme.surface,
          child: Padding(
            padding: padding,
            child: Column(
              children: [
                const _ModuleHeroCard(
                  eyebrow: 'Gestión',
                  title: 'Ver suplidores',
                  subtitle:
                      'Revisa el historial de suplidores en una vista compacta, limpia y fácil de consultar.',
                ),
                const SizedBox(height: 18),
                Expanded(
                  child: isWide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(child: listCard),
                            const SizedBox(width: 18),
                            SizedBox(width: 360, child: detailCard),
                          ],
                        )
                      : Column(
                          children: [
                            Expanded(child: listCard),
                            const SizedBox(height: 18),
                            SizedBox(height: 260, child: detailCard),
                          ],
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ModuleHeroCard extends StatelessWidget {
  const _ModuleHeroCard({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
  });

  final String eyebrow;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.9)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              eyebrow.toUpperCase(),
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurface.withOpacity(0.66),
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SupplierStatusBadge extends StatelessWidget {
  const _SupplierStatusBadge({required this.supplier});

  final SupplierModel supplier;

  @override
  Widget build(BuildContext context) {
    final isActive = supplier.isActive && !supplier.isDeleted;
    final bg = supplier.isDeleted
        ? const Color(0xFFFEE2E2)
        : (isActive ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7));
    final fg = supplier.isDeleted
        ? const Color(0xFFB91C1C)
        : (isActive ? const Color(0xFF166534) : const Color(0xFF92400E));
    final label = supplier.isDeleted
        ? 'Eliminado'
        : (isActive ? 'Activo' : 'Inactivo');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurface.withOpacity(0.56),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 5,
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyStateCard extends StatelessWidget {
  const _EmptyStateCard({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.9)),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 42, color: scheme.onSurface.withOpacity(0.35)),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurface.withOpacity(0.58),
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
