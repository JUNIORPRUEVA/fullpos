import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../fiscal_receipts/data/fiscal_receipt_models.dart';
import '../../fiscal_receipts/data/fiscal_receipt_repository.dart';
import 'settings_layout.dart';

class FiscalReceiptsSettingsPage extends StatefulWidget {
  const FiscalReceiptsSettingsPage({super.key});

  @override
  State<FiscalReceiptsSettingsPage> createState() =>
      _FiscalReceiptsSettingsPageState();
}

class _FiscalReceiptsSettingsPageState
    extends State<FiscalReceiptsSettingsPage> {
  bool _loading = true;
  FiscalReceiptSettingsModel _settings =
      const FiscalReceiptSettingsModel(enabled: false);
  List<FiscalReceiptTypeModel> _types = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final settings = await FiscalReceiptRepository.getSettings();
    final types = await FiscalReceiptRepository.getAllTypes();
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _types = types;
      _loading = false;
    });
  }

  Future<void> _toggleEnabled(bool enabled) async {
    final next = _settings.copyWith(enabled: enabled);
    await FiscalReceiptRepository.saveSettings(next);
    if (!mounted) return;
    setState(() => _settings = next);
  }

  Future<void> _setDefault(int? id) async {
    await FiscalReceiptRepository.setDefaultType(id);
    await _load();
  }

  Future<void> _openEditor([FiscalReceiptTypeModel? type]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _FiscalReceiptTypeDialog(type: type),
    );
    if (saved == true) await _load();
  }

  Future<void> _toggleType(FiscalReceiptTypeModel type) async {
    await FiscalReceiptRepository.saveType(
      type.copyWith(
        isActive: !type.isActive,
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    await _load();
  }

  Future<void> _deleteType(FiscalReceiptTypeModel type) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar comprobante'),
        content: Text(
          'Si este comprobante ya fue usado se desactivará para conservar el historial.\n\n¿Deseas continuar con "${type.name}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continuar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await FiscalReceiptRepository.softDeleteType(type.id!);
    await _load();
  }

  Future<void> _showHistory(FiscalReceiptTypeModel type) async {
    final rows = await FiscalReceiptRepository.getUsageHistory(type.id!);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Historial ${type.name}'),
        content: SizedBox(
          width: 560,
          child: rows.isEmpty
              ? const Text('Este comprobante todavía no tiene usos.')
              : SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final row in rows)
                        ListTile(
                          dense: true,
                          title: Text(row['ncf_full']?.toString() ?? ''),
                          subtitle: Text(
                            [
                              if ((row['customer_name'] ?? '')
                                  .toString()
                                  .trim()
                                  .isNotEmpty)
                                row['customer_name'].toString(),
                              'Venta #${row['sale_id']}',
                              _formatMs(row['created_at_ms'] as int?),
                            ].where((e) => e.trim().isNotEmpty).join(' · '),
                          ),
                        ),
                    ],
                  ),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: SettingsLayout.brandedTheme(context),
      child: LayoutBuilder(
        builder: (context, constraints) => SettingsLayout.pageFrame(
          constraints,
          max: 1080,
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.receipt_long_outlined,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Comprobantes',
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ),
                          FilledButton.icon(
                            onPressed: () => _openEditor(),
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Nuevo comprobante'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _SettingsCard(
                        child: Column(
                          children: [
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Usar comprobantes fiscales'),
                              subtitle: const Text(
                                'Cuando está activo, ventas puede asignar NCF locales al cobrar.',
                              ),
                              value: _settings.enabled,
                              onChanged: _toggleEnabled,
                            ),
                            const Divider(),
                            DropdownButtonFormField<int?>(
                              value: _settings.defaultReceiptTypeId,
                              decoration: const InputDecoration(
                                labelText: 'Comprobante por defecto',
                                prefixIcon: Icon(Icons.bookmark_outline),
                              ),
                              items: [
                                const DropdownMenuItem<int?>(
                                  value: null,
                                  child: Text('Ninguno'),
                                ),
                                for (final type in _types.where((t) => t.isAvailable))
                                  DropdownMenuItem<int?>(
                                    value: type.id,
                                    child: Text('${type.name} (${type.code})'),
                                  ),
                              ],
                              onChanged: _setDefault,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (_types.isEmpty)
                        _SettingsCard(
                          child: Column(
                            children: [
                              const Icon(Icons.receipt_outlined, size: 42),
                              const SizedBox(height: 8),
                              const Text('No hay comprobantes configurados.'),
                              const SizedBox(height: 12),
                              OutlinedButton.icon(
                                onPressed: () => _openEditor(),
                                icon: const Icon(Icons.add),
                                label: const Text('Crear comprobante'),
                              ),
                            ],
                          ),
                        )
                      else
                        _SettingsCard(
                          child: Column(
                            children: [
                              for (final type in _types) ...[
                                _ReceiptTypeRow(
                                  type: type,
                                  isDefault:
                                      _settings.defaultReceiptTypeId == type.id,
                                  onEdit: () => _openEditor(type),
                                  onToggle: () => _toggleType(type),
                                  onDelete: () => _deleteType(type),
                                  onHistory: () => _showHistory(type),
                                ),
                                if (type != _types.last) const Divider(),
                              ],
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

class _ReceiptTypeRow extends StatelessWidget {
  const _ReceiptTypeRow({
    required this.type,
    required this.isDefault,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
    required this.onHistory,
  });

  final FiscalReceiptTypeModel type;
  final bool isDefault;
  final VoidCallback onEdit;
  final VoidCallback onToggle;
  final VoidCallback onDelete;
  final VoidCallback onHistory;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = type.isExhausted
        ? 'Agotado'
        : type.isExpired
        ? 'Vencido'
        : type.isActive
        ? 'Activo'
        : 'Inactivo';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          CircleAvatar(
            radius: 19,
            backgroundColor: theme.colorScheme.primary.withOpacity(0.09),
            child: Text(
              type.code.length > 3 ? type.code.substring(0, 3) : type.code,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.primary,
                fontSize: 11,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        type.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (isDefault) ...[
                      const SizedBox(width: 6),
                      const Chip(
                        label: Text('Default'),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  'Prefijo ${type.prefix} · Próximo ${type.nextReceiptNumber} · ${type.startNumber}-${type.endNumber} · $status',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Historial',
            onPressed: onHistory,
            icon: const Icon(Icons.history_outlined),
          ),
          IconButton(
            tooltip: 'Editar',
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: type.isActive ? 'Desactivar' : 'Activar',
            onPressed: onToggle,
            icon: Icon(type.isActive ? Icons.toggle_on : Icons.toggle_off),
          ),
          IconButton(
            tooltip: 'Eliminar',
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }
}

class _FiscalReceiptTypeDialog extends StatefulWidget {
  const _FiscalReceiptTypeDialog({this.type});

  final FiscalReceiptTypeModel? type;

  @override
  State<_FiscalReceiptTypeDialog> createState() =>
      _FiscalReceiptTypeDialogState();
}

class _FiscalReceiptTypeDialogState extends State<_FiscalReceiptTypeDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _code;
  late final TextEditingController _prefix;
  late final TextEditingController _start;
  late final TextEditingController _next;
  late final TextEditingController _end;
  late final TextEditingController _note;
  DateTime? _expiration;
  bool _active = true;
  bool _requiresTaxId = false;
  bool _requiresName = false;
  bool _allowFinalConsumer = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final type = widget.type;
    _name = TextEditingController(text: type?.name ?? '');
    _code = TextEditingController(text: type?.code ?? '');
    _prefix = TextEditingController(text: type?.prefix ?? '');
    _start = TextEditingController(text: (type?.startNumber ?? 1).toString());
    _next = TextEditingController(text: (type?.nextNumber ?? 1).toString());
    _end = TextEditingController(text: (type?.endNumber ?? 100).toString());
    _note = TextEditingController(text: type?.note ?? '');
    _expiration = type?.expiresAtMs == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(type!.expiresAtMs!);
    _active = type?.isActive ?? true;
    _requiresTaxId = type?.requiresCustomerTaxId ?? false;
    _requiresName = type?.requiresCustomerName ?? false;
    _allowFinalConsumer = type?.allowFinalConsumer ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _prefix.dispose();
    _start.dispose();
    _next.dispose();
    _end.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiration ?? DateTime.now().add(const Duration(days: 365)),
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (picked != null) setState(() => _expiration = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final base = widget.type;
      final type = FiscalReceiptTypeModel(
        id: base?.id,
        name: _name.text.trim(),
        code: _code.text.trim().toUpperCase(),
        prefix: _prefix.text.trim().toUpperCase(),
        startNumber: int.parse(_start.text.trim()),
        nextNumber: int.parse(_next.text.trim()),
        endNumber: int.parse(_end.text.trim()),
        expiresAtMs: _expiration == null
            ? null
            : DateTime(_expiration!.year, _expiration!.month, _expiration!.day)
                .millisecondsSinceEpoch,
        requiresCustomerTaxId: _requiresTaxId,
        requiresCustomerName: _requiresName,
        allowFinalConsumer: _allowFinalConsumer,
        isDefault: base?.isDefault ?? false,
        isActive: _active,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
        createdAtMs: base?.createdAtMs ?? now,
        updatedAtMs: now,
      );
      await FiscalReceiptRepository.saveType(type);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.type == null ? 'Nuevo comprobante' : 'Editar comprobante'),
      content: SizedBox(
        width: 620,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Nombre visible'),
                  validator: _required,
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _code,
                        decoration: const InputDecoration(labelText: 'Código fiscal'),
                        validator: _required,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _prefix,
                        decoration: const InputDecoration(labelText: 'Prefijo'),
                        validator: _required,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: _numberField(_start, 'Desde')),
                    const SizedBox(width: 10),
                    Expanded(child: _numberField(_next, 'Próximo')),
                    const SizedBox(width: 10),
                    Expanded(child: _numberField(_end, 'Hasta')),
                  ],
                ),
                const SizedBox(height: 10),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    _expiration == null
                        ? 'Sin vencimiento'
                        : 'Vence ${DateFormat('dd/MM/yyyy').format(_expiration!)}',
                  ),
                  leading: const Icon(Icons.event_outlined),
                  trailing: TextButton(
                    onPressed: _pickDate,
                    child: const Text('Elegir'),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Activo'),
                  value: _active,
                  onChanged: (v) => setState(() => _active = v),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Requiere cliente con RNC/Cédula'),
                  value: _requiresTaxId,
                  onChanged: (v) => setState(() => _requiresTaxId = v ?? false),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Requiere nombre fiscal del cliente'),
                  value: _requiresName,
                  onChanged: (v) => setState(() => _requiresName = v ?? false),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Permitir consumidor final'),
                  value: _allowFinalConsumer,
                  onChanged: (v) =>
                      setState(() => _allowFinalConsumer = v ?? true),
                ),
                TextFormField(
                  controller: _note,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Nota opcional'),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Guardando...' : 'Guardar'),
        ),
      ],
    );
  }

  Widget _numberField(TextEditingController controller, String label) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: label),
      validator: (value) {
        final parsed = int.tryParse((value ?? '').trim());
        if (parsed == null || parsed < 1) return 'Número válido requerido';
        return null;
      },
    );
  }

  String? _required(String? value) {
    return (value ?? '').trim().isEmpty ? 'Requerido' : null;
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.55)),
      ),
      child: child,
    );
  }
}

String _formatMs(int? value) {
  if (value == null) return '';
  return DateFormat('dd/MM/yyyy HH:mm').format(
    DateTime.fromMillisecondsSinceEpoch(value),
  );
}
