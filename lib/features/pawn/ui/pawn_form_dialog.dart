import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/errors/error_handler.dart';
import '../../clients/data/client_model.dart';
import '../../clients/data/clients_repository.dart';
import '../../sales/ui/dialogs/client_picker_dialog.dart';
import '../data/pawn_model.dart';
import '../data/pawn_repository.dart';

class PawnFormDialog extends StatefulWidget {
  final PawnModel? pawn;

  const PawnFormDialog({super.key, this.pawn});

  @override
  State<PawnFormDialog> createState() => _PawnFormDialogState();
}

class _PawnFormDialogState extends State<PawnFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  final _amountController = TextEditingController();

  bool _isLoading = false;
  List<ClientModel> _clients = [];
  ClientModel? _selectedClient;
  String _status = 'activo';

  bool get _isEditing => widget.pawn != null;

  @override
  void initState() {
    super.initState();
    final pawn = widget.pawn;
    if (pawn != null) {
      _descriptionController.text = pawn.descripcion;
      _amountController.text = pawn.monto.toStringAsFixed(2);
      _status = pawn.status;
    }
    _loadClients();
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _loadClients() async {
    try {
      final clients = await ClientsRepository.getAll();
      if (!mounted) return;

      final currentClientId = widget.pawn?.clientId;
      setState(() {
        _clients = clients;
        if (currentClientId != null) {
          _selectedClient = clients
              .where((client) => client.id == currentClientId)
              .firstOrNull;
        }
      });
    } catch (e, st) {
      if (!mounted) return;
      await ErrorHandler.instance.handle(
        e,
        stackTrace: st,
        context: context,
        onRetry: _loadClients,
        module: 'pawn/load_clients',
      );
    }
  }

  Future<void> _pickClient() async {
    final result = await showDialog<ClientModel>(
      context: context,
      builder: (context) => ClientPickerDialog(clients: _clients),
    );

    if (result == null || !mounted) return;

    setState(() {
      _selectedClient = result;
      if (_clients.every((client) => client.id != result.id)) {
        _clients = [..._clients, result];
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedClient?.id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona un cliente para continuar.')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final amount = double.parse(_amountController.text.trim());
      final now = DateTime.now().millisecondsSinceEpoch;
      final draft = PawnModel(
        id: widget.pawn?.id,
        clientId: _selectedClient!.id!,
        descripcion: _descriptionController.text.trim(),
        monto: amount,
        status: _status,
        createdAtMs: widget.pawn?.createdAtMs ?? now,
      );

      if (_isEditing) {
        await PawnRepository.update(draft);
        if (!mounted) return;
        Navigator.of(context).pop(draft);
      } else {
        final id = await PawnRepository.insert(draft);
        if (!mounted) return;
        Navigator.of(context).pop(
          PawnModel(
            id: id,
            clientId: draft.clientId,
            descripcion: draft.descripcion,
            monto: draft.monto,
            status: draft.status,
            createdAtMs: draft.createdAtMs,
          ),
        );
      }
    } catch (e, st) {
      if (!mounted) return;
      await ErrorHandler.instance.handle(
        e,
        stackTrace: st,
        context: context,
        onRetry: _save,
        module: 'pawn/form',
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSizes.paddingXL),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppColors.goldSoft,
                        borderRadius: BorderRadius.circular(AppSizes.radiusL),
                      ),
                      child: const Icon(
                        Icons.diamond_outlined,
                        color: AppColors.goldDark,
                      ),
                    ),
                    const SizedBox(width: AppSizes.spaceM),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _isEditing ? 'Editar empeño' : 'Nuevo empeño',
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: AppSizes.spaceXS),
                          const Text(
                            'Registra la prenda, el monto entregado y el cliente asociado.',
                            style: TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSizes.spaceXL),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSizes.paddingM),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceLightVariant,
                    borderRadius: BorderRadius.circular(AppSizes.radiusL),
                    border: Border.all(color: AppColors.surfaceLightBorder),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Cliente',
                              style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: AppSizes.spaceXS),
                            Text(
                              _selectedClient?.nombre ??
                                  'Ningún cliente seleccionado',
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if ((_selectedClient?.telefono ?? '')
                                .isNotEmpty) ...[
                              const SizedBox(height: AppSizes.spaceXS),
                              Text(
                                _selectedClient!.telefono!,
                                style: const TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: AppSizes.spaceM),
                      OutlinedButton.icon(
                        onPressed: _pickClient,
                        icon: const Icon(Icons.person_search_outlined),
                        label: Text(
                          _selectedClient == null ? 'Seleccionar' : 'Cambiar',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSizes.spaceL),
                TextFormField(
                  controller: _descriptionController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Descripción de la prenda',
                    hintText: 'Ej: Cadena de oro 14k con dije',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Describe la prenda o garantía.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppSizes.spaceM),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _amountController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Monto entregado',
                          hintText: '0.00',
                          border: OutlineInputBorder(),
                          prefixText: '4 ',
                        ),
                        validator: (value) {
                          final parsed = double.tryParse(value?.trim() ?? '');
                          if (parsed == null || parsed <= 0) {
                            return 'Ingresa un monto válido.';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: AppSizes.spaceM),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _status,
                        decoration: const InputDecoration(
                          labelText: 'Estado',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'activo',
                            child: Text('Activo'),
                          ),
                          DropdownMenuItem(
                            value: 'renovado',
                            child: Text('Renovado'),
                          ),
                          DropdownMenuItem(
                            value: 'cerrado',
                            child: Text('Cerrado'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() => _status = value);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSizes.spaceXL),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _isLoading
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: const Text('Cancelar'),
                    ),
                    const SizedBox(width: AppSizes.spaceS),
                    ElevatedButton.icon(
                      onPressed: _isLoading ? null : _save,
                      icon: _isLoading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_outlined),
                      label: Text(
                        _isEditing ? 'Guardar cambios' : 'Registrar empeño',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.gold,
                        foregroundColor: AppColors.bgDark,
                      ),
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
