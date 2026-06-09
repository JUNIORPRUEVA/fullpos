import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/errors/error_handler.dart';
import '../data/client_model.dart';
import '../data/clients_repository.dart';
import '../utils/phone_validator.dart';
import '../utils/rnc_validator.dart';

/// Diálogo de formulario para crear/editar clientes
class ClientFormDialog extends StatefulWidget {
  final ClientModel? client;
  final Future<ClientModel?> Function(String phone)? getByPhone;
  final Future<ClientModel> Function(ClientModel client, bool isEditing)?
  saveClient;
  final double? dialogWidth;
  final double? dialogHeight;
  final EdgeInsets? insetPadding;
  final AlignmentGeometry? alignment;
  final BorderRadius? borderRadius;

  const ClientFormDialog({
    super.key,
    this.client,
    this.getByPhone,
    this.saveClient,
    this.dialogWidth,
    this.dialogHeight,
    this.insetPadding,
    this.alignment,
    this.borderRadius,
  });

  @override
  State<ClientFormDialog> createState() => _ClientFormDialogState();
}

class _ClientFormDialogState extends State<ClientFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nombreController = TextEditingController();
  final _telefonoController = TextEditingController();
  final _direccionController = TextEditingController();
  final _rncController = TextEditingController();
  final _cedulaController = TextEditingController();

  bool _isActive = true;
  bool _hasCredit = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.client != null) {
      _nombreController.text = widget.client!.nombre;
      _telefonoController.text = widget.client!.telefono ?? '';
      _direccionController.text = widget.client!.direccion ?? '';
      _rncController.text = widget.client!.rnc ?? '';
      _cedulaController.text = widget.client!.cedula ?? '';
      _isActive = widget.client!.isActive;
      _hasCredit = widget.client!.hasCredit;
    }
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _telefonoController.dispose();
    _direccionController.dispose();
    _rncController.dispose();
    _cedulaController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final now = DateTime.now().millisecondsSinceEpoch;

      final rawPhone = _telefonoController.text.trim();
      final normalizedPhone = rawPhone.isEmpty
          ? null
          : PhoneValidator.normalizeRDPhone(rawPhone);
      final rawRnc = _rncController.text.trim();
      final normalizedRnc = rawRnc.isEmpty
          ? null
          : RncValidator.normalize(rawRnc);

      if (normalizedPhone == null && normalizedRnc == null) {
        throw ArgumentError(
          'Debe indicar al menos un teléfono o un RNC válido',
        );
      }

      if (rawPhone.isNotEmpty && normalizedPhone == null) {
        throw ArgumentError(
          'Teléfono inválido. Use 10 dígitos RD (ej: 809-555-1234)',
        );
      }

      if (rawRnc.isNotEmpty && normalizedRnc == null) {
        throw ArgumentError('RNC inválido. Debe contener 9 dígitos');
      }

      // Si estamos CREANDO (no editando), verificar duplicados ANTES de intentar guardar
      if (widget.client == null) {
        final getByPhone = widget.getByPhone ?? ClientsRepository.getByPhone;
        final existingClient = normalizedPhone == null
            ? null
            : await getByPhone(normalizedPhone);
        final existingBusiness = normalizedRnc == null
            ? null
            : await ClientsRepository.getByRnc(normalizedRnc);

        if (existingClient != null &&
            existingBusiness != null &&
            existingClient.id != existingBusiness.id) {
          throw ArgumentError(
            'El teléfono y el RNC pertenecen a clientes distintos. Revise los datos.',
          );
        }

        final duplicatedClient = existingClient ?? existingBusiness;

        if (duplicatedClient != null && duplicatedClient.isActive) {
          final duplicateMessage = existingClient != null
              ? 'Ya existe un cliente con este teléfono:'
              : 'Ya existe un cliente con estos datos:';

          if (!mounted) return;
          setState(() => _isLoading = false);

          if (!mounted) return;

          // Mostrar alerta con información del cliente existente
          await showDialog<void>(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              title: Row(
                children: [
                  Icon(Icons.info_outline, color: AppColors.gold),
                  const SizedBox(width: 8),
                  const Text('Cliente ya registrado'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    duplicateMessage,
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceLightVariant,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.surfaceLightBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Nombre: ${duplicatedClient.nombre}',
                          style: const TextStyle(fontSize: 15),
                        ),
                        if ((duplicatedClient.telefono ?? '')
                            .trim()
                            .isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Teléfono: ${PhoneValidator.formatRDPhone(duplicatedClient.telefono ?? "") ?? duplicatedClient.telefono}',
                            style: const TextStyle(fontSize: 15),
                          ),
                        ],
                        if ((duplicatedClient.rnc ?? '').trim().isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            'RNC: ${duplicatedClient.rnc}',
                            style: const TextStyle(fontSize: 15),
                          ),
                        ],
                        if (duplicatedClient.direccion?.isNotEmpty ??
                            false) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Dirección: ${duplicatedClient.direccion}',
                            style: const TextStyle(fontSize: 15),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No se pueden crear clientes duplicados. '
                    'Puedes buscar y editar este cliente desde la lista.',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                ],
              ),
              actions: [
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Entendido'),
                ),
              ],
            ),
          );

          // No continuar con la creación
          return;
        }
      }

      final client = ClientModel(
        id: widget.client?.id,
        nombre: _nombreController.text.trim(),
        telefono: normalizedPhone,
        direccion: _direccionController.text.trim().isEmpty
            ? null
            : _direccionController.text.trim(),
        rnc: normalizedRnc,
        cedula: _cedulaController.text.trim().isEmpty
            ? null
            : _cedulaController.text.trim(),
        isActive: _isActive,
        hasCredit: _hasCredit,
        createdAtMs: widget.client?.createdAtMs ?? now,
        updatedAtMs: now,
      );

      if (widget.saveClient != null) {
        final saved = await widget.saveClient!(client, widget.client != null);
        if (mounted) Navigator.of(context).pop(saved);
        return;
      }

      if (widget.client == null) {
        // Crear nuevo cliente
        final clientId = await ClientsRepository.create(client);

        // Obtener el cliente creado para devolverlo
        final createdClient = await ClientsRepository.getById(clientId);

        if (mounted) {
          Navigator.of(
            context,
          ).pop(createdClient ?? client.copyWith(id: clientId));
        }
      } else {
        // Actualizar cliente existente
        await ClientsRepository.update(client);

        if (mounted) {
          // Devolver el cliente actualizado
          Navigator.of(context).pop(client);
        }
      }
    } catch (e, st) {
      await ErrorHandler.instance.handle(
        e,
        stackTrace: st,
        context: context,
        onRetry: _handleSave,
        module: 'clients/form',
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.client != null;

    return Dialog(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 600),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(AppSizes.paddingXL),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Título
                  Row(
                    children: [
                      Icon(
                        isEditing ? Icons.edit : Icons.person_add,
                        color: AppColors.gold,
                        size: 28,
                      ),
                      const SizedBox(width: AppSizes.spaceM),
                      Text(
                        isEditing ? 'Editar Cliente' : 'Nuevo Cliente',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSizes.spaceXL),

                  // Nombre (requerido)
                  TextFormField(
                    controller: _nombreController,
                    decoration: const InputDecoration(
                      labelText: 'Nombre *',
                      prefixIcon: Icon(Icons.person),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'El nombre es obligatorio';
                      }
                      return null;
                    },
                    enabled: !_isLoading,
                  ),
                  const SizedBox(height: AppSizes.spaceM),

                  // Teléfono (requerido)
                  TextFormField(
                    controller: _telefonoController,
                    decoration: InputDecoration(
                      labelText: 'Teléfono',
                      hintText: 'Ej: 8095551234, 809-555-1234, +1 809 555 1234',
                      helperText: 'Opcional si registrarás la empresa con RNC',
                      prefixIcon: const Icon(Icons.phone),
                    ),
                    keyboardType: TextInputType.phone,
                    validator: (value) {
                      final rawPhone = value?.trim() ?? '';
                      final rawRnc = _rncController.text.trim();
                      if (rawPhone.isEmpty && rawRnc.isEmpty) {
                        return 'Indique teléfono o RNC';
                      }

                      // Debe poder normalizarse a +1XXXXXXXXXX (10 dígitos RD)
                      if (rawPhone.isNotEmpty &&
                          PhoneValidator.normalizeRDPhone(rawPhone) == null) {
                        return 'Teléfono inválido. Use 10 dígitos RD (ej: 809-555-1234)';
                      }

                      return null;
                    },
                    enabled: !_isLoading,
                  ),
                  const SizedBox(height: AppSizes.spaceM),

                  // Dirección
                  TextFormField(
                    controller: _direccionController,
                    decoration: const InputDecoration(
                      labelText: 'Dirección',
                      prefixIcon: Icon(Icons.location_on),
                    ),
                    maxLines: 2,
                    enabled: !_isLoading,
                  ),
                  const SizedBox(height: AppSizes.spaceM),

                  // RNC
                  TextFormField(
                    controller: _rncController,
                    decoration: const InputDecoration(
                      labelText: 'RNC',
                      helperText: 'Obligatorio para empresa / factura E31',
                      prefixIcon: Icon(Icons.business),
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      final rawRnc = value?.trim() ?? '';
                      final rawPhone = _telefonoController.text.trim();
                      if (rawRnc.isEmpty && rawPhone.isEmpty) {
                        return 'Indique RNC o teléfono';
                      }
                      if (rawRnc.isNotEmpty &&
                          !RncValidator.isValidBasic(rawRnc)) {
                        return 'RNC inválido. Debe contener 9 dígitos';
                      }
                      return null;
                    },
                    enabled: !_isLoading,
                  ),
                  const SizedBox(height: AppSizes.spaceM),

                  // Cédula
                  TextFormField(
                    controller: _cedulaController,
                    decoration: const InputDecoration(
                      labelText: 'Cédula',
                      prefixIcon: Icon(Icons.badge),
                    ),
                    enabled: !_isLoading,
                  ),
                  const SizedBox(height: AppSizes.spaceL),

                  const SizedBox(height: AppSizes.spaceXL),

                  // Botones
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: _isLoading
                            ? null
                            : () => Navigator.of(context).pop(null),
                        child: const Text('Cancelar'),
                      ),
                      const SizedBox(width: AppSizes.spaceM),
                      ElevatedButton.icon(
                        onPressed: _isLoading ? null : _handleSave,
                        icon: _isLoading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.teal900,
                                ),
                              )
                            : const Icon(Icons.save),
                        label: Text(_isLoading ? 'Guardando...' : 'Guardar'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.gold,
                          foregroundColor: AppColors.teal900,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
