import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../../core/errors/error_handler.dart';
import '../../data/client_model.dart';
import '../../data/clients_repository.dart';
import '../../utils/phone_validator.dart';
import '../../utils/rnc_validator.dart';

Future<ClientModel?> showClientFormSidePanel(
  BuildContext context, {
  ClientModel? initialClient,
  double? panelWidth,
}) {
  final screenSize = MediaQuery.sizeOf(context);
  final effectivePanelWidth =
      panelWidth ??
      (screenSize.width >= 1600
          ? 440.0
          : (screenSize.width >= 1200 ? 400.0 : 360.0)
                .clamp(320.0, screenSize.width - 16)
                .toDouble());

  return showGeneralDialog<ClientModel>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withOpacity(0.08),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      return Material(
        color: Colors.transparent,
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: () => Navigator.of(dialogContext).pop(),
                behavior: HitTestBehavior.translucent,
                child: const SizedBox.expand(),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                ignoring: true,
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 3, sigmaY: 3),
                  child: Container(color: Colors.white.withOpacity(0.04)),
                ),
              ),
            ),
            Positioned(
              top: 0,
              right: 0,
              bottom: 0,
              width: effectivePanelWidth,
              child: Material(
                color: Colors.transparent,
                elevation: 24,
                shadowColor: Colors.black.withOpacity(0.24),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(18),
                  bottomLeft: Radius.circular(18),
                ),
                child: ClipRRect(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(18),
                    bottomLeft: Radius.circular(18),
                  ),
                  child: ClientFormSidePanel(
                    initialClient: initialClient,
                    onClose: () => Navigator.of(dialogContext).pop(),
                    onSaved: (client) =>
                        Navigator.of(dialogContext).pop(client),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.08, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class ClientFormSidePanel extends StatefulWidget {
  const ClientFormSidePanel({
    super.key,
    required this.onClose,
    required this.onSaved,
    this.initialClient,
  });

  final VoidCallback onClose;
  final ValueChanged<ClientModel> onSaved;
  final ClientModel? initialClient;

  @override
  State<ClientFormSidePanel> createState() => _ClientFormSidePanelState();
}

class _ClientFormSidePanelState extends State<ClientFormSidePanel> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _taxIdController = TextEditingController();
  final _addressController = TextEditingController();
  bool _isSaving = false;

  bool get _isEditing => widget.initialClient != null;

  @override
  void initState() {
    super.initState();
    final client = widget.initialClient;
    if (client == null) return;
    _nameController.text = client.nombre;
    _phoneController.text = client.telefono ?? '';
    _taxIdController.text = client.rnc ?? client.cedula ?? '';
    _addressController.text = client.direccion ?? '';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _taxIdController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_isSaving || !_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final rawPhone = _phoneController.text.trim();
      final normalizedPhone = rawPhone.isEmpty
          ? null
          : PhoneValidator.normalizePhone(rawPhone);

      final rawTaxId = _taxIdController.text.trim();
      final normalizedTaxDigits = rawTaxId.replaceAll(RegExp(r'\D'), '');
      final rnc = normalizedTaxDigits.length == 9
          ? RncValidator.normalize(normalizedTaxDigits)
          : null;
      final cedula = normalizedTaxDigits.isNotEmpty && rnc == null
          ? normalizedTaxDigits
          : null;

      final baseClient = widget.initialClient;
      final client = ClientModel(
        id: baseClient?.id,
        nombre: _nameController.text.trim(),
        telefono: normalizedPhone,
        direccion: _addressController.text.trim().isEmpty
            ? null
            : _addressController.text.trim(),
        rnc: rnc,
        cedula: cedula,
        isActive: baseClient?.isActive ?? true,
        hasCredit: baseClient?.hasCredit ?? false,
        createdAtMs: baseClient?.createdAtMs ?? now,
        updatedAtMs: now,
      );

      if (_isEditing) {
        await ClientsRepository.update(client);
        final updatedClient = await ClientsRepository.getById(client.id!);
        if (!mounted) return;
        widget.onSaved(updatedClient ?? client);
        return;
      }

      final clientId = await ClientsRepository.create(client);
      final createdClient = await ClientsRepository.getById(clientId);
      if (!mounted) return;
      widget.onSaved(createdClient ?? client.copyWith(id: clientId));
    } catch (e, st) {
      if (!mounted) return;
      await ErrorHandler.instance.handle(
        e,
        stackTrace: st,
        context: context,
        onRetry: _save,
        module: 'clients/form_side_panel',
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final contentMaxWidth = (constraints.maxWidth - 32).clamp(320.0, 460.0);

        return Material(
          color: Colors.white,
          child: SafeArea(
            left: false,
            top: false,
            bottom: false,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 18, 12, 14),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE9F1FF),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.person_add_alt_1_rounded,
                          color: Color(0xFF1A56DB),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _isEditing ? 'Editar cliente' : 'Nuevo cliente',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF17324D),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _isEditing
                                  ? 'Actualiza los datos del cliente desde esta columna'
                                  : 'Crea un cliente rapido para esta factura',
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF6B7C8E),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: widget.onClose,
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: contentMaxWidth),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            children: [
                              TextFormField(
                                controller: _nameController,
                                decoration: _panelFieldDecoration(
                                  'Nombre o razón social *',
                                  Icons.person_outline,
                                ),
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'El nombre es obligatorio';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _phoneController,
                                keyboardType: TextInputType.phone,
                                decoration: _panelFieldDecoration(
                                  'Teléfono',
                                  Icons.phone_outlined,
                                ),
                                validator: (value) {
                                  final phone = value?.trim() ?? '';
                                  final taxId = _taxIdController.text.trim();
                                  if (phone.isEmpty && taxId.isEmpty) {
                                    return 'Indica teléfono o RNC/Cédula';
                                  }
                                  if (phone.isNotEmpty &&
                                      PhoneValidator.normalizePhone(phone) ==
                                          null) {
                                    return 'Teléfono inválido';
                                  }
                                  return null;
                                },
                              ),

                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _taxIdController,
                                decoration: _panelFieldDecoration(
                                  'RNC o Cédula',
                                  Icons.badge_outlined,
                                ),
                                validator: (value) {
                                  final taxId = value?.trim() ?? '';
                                  final phone = _phoneController.text.trim();
                                  if (taxId.isEmpty && phone.isEmpty) {
                                    return 'Indica teléfono o RNC/Cédula';
                                  }
                                  final digits = taxId.replaceAll(
                                    RegExp(r'\D'),
                                    '',
                                  );
                                  if (digits.isNotEmpty &&
                                      digits.length != 9 &&
                                      digits.length != 11) {
                                    return 'Usa 9 dígitos para RNC o 11 para cédula';
                                  }
                                  if (digits.length == 9 &&
                                      !RncValidator.isValidBasic(digits)) {
                                    return 'RNC inválido';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _addressController,
                                maxLines: 2,
                                decoration: _panelFieldDecoration(
                                  'Dirección',
                                  Icons.location_on_outlined,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: contentMaxWidth),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _isSaving ? null : widget.onClose,
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(44),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text('Cancelar'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            onPressed: _isSaving ? null : _save,
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(44),
                              backgroundColor: const Color(0xFF1A56DB),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: _isSaving
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text(
                                    _isEditing
                                        ? 'Guardar cambios'
                                        : 'Guardar cliente',
                                  ),
                          ),
                        ),
                      ],
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

  InputDecoration _panelFieldDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    );
  }
}
