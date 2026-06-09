import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../../../core/ui/dialog_keyboard_shortcuts.dart';
import '../../../clients/data/client_model.dart';
import '../../../clients/ui/client_form_dialog.dart';

/// Dialogo de seleccion de cliente.
class ClientPickerDialog extends StatefulWidget {
  final List<ClientModel> clients;
  final Future<ClientModel?> Function()? onCreateClient;
  final double? dialogWidth;
  final double? dialogHeight;
  final EdgeInsets? insetPadding;
  final AlignmentGeometry? alignment;
  final BorderRadius? borderRadius;

  const ClientPickerDialog({
    super.key,
    required this.clients,
    this.onCreateClient,
    this.dialogWidth,
    this.dialogHeight,
    this.insetPadding,
    this.alignment,
    this.borderRadius,
  });

  @override
  State<ClientPickerDialog> createState() => _ClientPickerDialogState();
}

class _ClientPickerDialogState extends State<ClientPickerDialog> {
  final _searchController = TextEditingController();
  final _listController = ScrollController();
  List<ClientModel> _filteredClients = [];

  bool _isBusinessClient(ClientModel client) => client.isBusiness;

  String _clientTypeLabel(ClientModel client) => client.entityLabel;

  String _clientSupportingLine(ClientModel client) {
    final parts = <String>[];
    final document = client.documentLabel;
    final phone = client.normalizedPhone;

    if (document != null) parts.add(document);
    if (phone != null) parts.add(phone);

    if (parts.isNotEmpty) return parts.join('  •  ');

    final address = client.normalizedAddress;
    if (address != null) return address;

    return 'Consumidor final sin datos adicionales';
  }

  @override
  void initState() {
    super.initState();
    _filteredClients = widget.clients;
    _searchController.addListener(_filterClients);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _listController.dispose();
    super.dispose();
  }

  void _filterClients() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredClients = widget.clients;
      } else {
        _filteredClients = widget.clients.where((client) {
          return client.nombre.toLowerCase().contains(query) ||
              (client.telefono?.contains(query) ?? false) ||
              (client.rnc?.toLowerCase().contains(query) ?? false) ||
              (client.cedula?.toLowerCase().contains(query) ?? false);
        }).toList();
      }
    });
  }

  Future<void> _createNewClient() async {
    final result = widget.onCreateClient != null
        ? await widget.onCreateClient!()
        : await showDialog<ClientModel>(
            context: context,
            builder: (context) => const ClientFormDialog(),
          );
    if (result != null && mounted) {
      Navigator.pop(context, result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final viewport = MediaQuery.sizeOf(context);
    final listHeight = math.min<double>(
      viewport.height * 0.58,
      math.max<double>(260, _filteredClients.length * 58),
    );

    return DialogKeyboardShortcuts(
      child: AlertDialog(
        backgroundColor: scheme.surface,
        insetPadding:
            widget.insetPadding ??
            const EdgeInsets.symmetric(horizontal: 32, vertical: 18),
        contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        titleTextStyle: theme.textTheme.titleLarge?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w800,
        ),
        contentTextStyle: theme.textTheme.bodyMedium?.copyWith(
          color: scheme.onSurface,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: widget.borderRadius ?? BorderRadius.circular(20),
        ),
        title: Row(
          children: [
            Icon(Icons.person_search_rounded, color: scheme.primary),
            const SizedBox(width: 8),
            const Text('Elegir cliente'),
            const Spacer(),
            FilledButton.tonalIcon(
              onPressed: _createNewClient,
              icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
              label: const Text('Nuevo'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: Icon(Icons.close_rounded, color: scheme.onSurface),
            ),
          ],
        ),
        content: SizedBox(
          width: widget.dialogWidth ?? 540,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _searchController,
                style: TextStyle(color: scheme.onSurface),
                decoration: InputDecoration(
                  hintText: 'Buscar por nombre, RNC, cédula o teléfono',
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    size: 20,
                    color: scheme.onSurfaceVariant,
                  ),
                  suffixIcon: _searchController.text.trim().isEmpty
                      ? null
                      : IconButton(
                          onPressed: () {
                            _searchController.clear();
                            _filterClients();
                          },
                          icon: const Icon(Icons.close_rounded, size: 18),
                        ),
                  filled: true,
                  fillColor: scheme.surfaceContainerLowest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: scheme.outlineVariant),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: scheme.outlineVariant),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: scheme.primary),
                  ),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: listHeight,
                child: _filteredClients.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.person_off_outlined,
                              size: 48,
                              color: scheme.onSurfaceVariant.withOpacity(0.55),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'No se encontraron clientes',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      )
                    : Container(
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: scheme.outlineVariant),
                        ),
                        child: Scrollbar(
                          controller: _listController,
                          thumbVisibility: true,
                          child: ListView.separated(
                            controller: _listController,
                            primary: false,
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            itemCount: _filteredClients.length,
                            separatorBuilder: (context, index) => Divider(
                              height: 1,
                              indent: 72,
                              endIndent: 14,
                              color: scheme.outlineVariant.withOpacity(0.55),
                            ),
                            itemBuilder: (context, index) {
                              final client = _filteredClients[index];
                              final isBusiness = _isBusinessClient(client);

                              return InkWell(
                                onTap: () => Navigator.pop(context, client),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 10,
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 42,
                                        height: 42,
                                        decoration: BoxDecoration(
                                          color: isBusiness
                                              ? scheme.primary.withOpacity(0.1)
                                              : scheme.secondary.withOpacity(
                                                  0.12,
                                                ),
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                        ),
                                        child: Icon(
                                          isBusiness
                                              ? Icons.apartment_rounded
                                              : Icons.person_rounded,
                                          color: isBusiness
                                              ? scheme.primary
                                              : scheme.secondary,
                                          size: 20,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    client.nombre,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: theme
                                                        .textTheme
                                                        .titleSmall
                                                        ?.copyWith(
                                                          color:
                                                              scheme.onSurface,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                        ),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 4,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: isBusiness
                                                        ? scheme.primary
                                                              .withOpacity(0.1)
                                                        : scheme.secondary
                                                              .withOpacity(
                                                                0.12,
                                                              ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          999,
                                                        ),
                                                  ),
                                                  child: Text(
                                                    _clientTypeLabel(client),
                                                    style: theme
                                                        .textTheme
                                                        .labelSmall
                                                        ?.copyWith(
                                                          color: isBusiness
                                                              ? scheme.primary
                                                              : scheme
                                                                    .secondary,
                                                          fontWeight:
                                                              FontWeight.w800,
                                                        ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              _clientSupportingLine(client),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: theme.textTheme.bodySmall
                                                  ?.copyWith(
                                                    color:
                                                        scheme.onSurfaceVariant,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Icon(
                                        Icons.chevron_right_rounded,
                                        size: 18,
                                        color: scheme.onSurfaceVariant,
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
