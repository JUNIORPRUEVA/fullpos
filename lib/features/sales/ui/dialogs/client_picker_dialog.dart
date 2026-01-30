import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../../../core/ui/dialog_keyboard_shortcuts.dart';
import '../../../clients/data/client_model.dart';
import '../../../clients/ui/client_form_dialog.dart';

/// Dialogo de seleccion de cliente.
class ClientPickerDialog extends StatefulWidget {
  final List<ClientModel> clients;

  const ClientPickerDialog({super.key, required this.clients});

  @override
  State<ClientPickerDialog> createState() => _ClientPickerDialogState();
}

class _ClientPickerDialogState extends State<ClientPickerDialog> {
  final _searchController = TextEditingController();
  final _listController = ScrollController();
  List<ClientModel> _filteredClients = [];

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
              (client.rnc?.toLowerCase().contains(query) ?? false);
        }).toList();
      }
    });
  }

  Future<void> _createNewClient() async {
    final result = await showDialog<ClientModel>(
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
    final listHeight =
        math.min<double>(360, math.max<double>(180, _filteredClients.length * 64));

    return DialogKeyboardShortcuts(
      child: AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 32),
        contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.person_search, color: scheme.primary),
            const SizedBox(width: 8),
            const Text('Clientes'),
            const Spacer(),
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      decoration: const InputDecoration(
                        hintText: 'Buscar cliente...',
                        prefixIcon: Icon(Icons.search, size: 20),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.person_add_alt_1_outlined),
                    tooltip: 'Agregar cliente',
                    onPressed: _createNewClient,
                  ),
                ],
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
                              Icons.person_off,
                              size: 48,
                              color: scheme.onSurface.withOpacity(0.4),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'No se encontraron clientes',
                              style: TextStyle(
                                color: scheme.onSurface.withOpacity(0.6),
                              ),
                            ),
                          ],
                        ),
                      )
                    : Scrollbar(
                        controller: _listController,
                        thumbVisibility: true,
                        child: ListView.builder(
                          controller: _listController,
                          primary: false,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          itemCount: _filteredClients.length,
                          itemBuilder: (context, index) {
                            final client = _filteredClients[index];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 6),
                              elevation: 1,
                              child: ListTile(
                                dense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 4,
                                ),
                                leading: CircleAvatar(
                                  radius: 18,
                                  backgroundColor: scheme.primaryContainer,
                                  child: Text(
                                    client.nombre[0].toUpperCase(),
                                    style: TextStyle(
                                      color: scheme.onPrimaryContainer,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                                title: Text(
                                  client.nombre,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  client.telefono ?? 'Sin telefono',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: scheme.onSurface.withOpacity(0.6),
                                  ),
                                ),
                                trailing: const Icon(
                                  Icons.arrow_forward_ios,
                                  size: 14,
                                ),
                                onTap: () => Navigator.pop(context, client),
                              ),
                            );
                          },
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
