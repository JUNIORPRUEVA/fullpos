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
    final viewport = MediaQuery.sizeOf(context);
    final listHeight = math.min<double>(
      viewport.height * 0.62,
      math.max<double>(260, _filteredClients.length * 64),
    );

    return DialogKeyboardShortcuts(
      child: AlertDialog(
        backgroundColor: Colors.white,
        insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 18),
        contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        titleTextStyle: const TextStyle(
          color: Colors.black,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
        contentTextStyle: const TextStyle(color: Colors.black, fontSize: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.person_search, color: Colors.black),
            const SizedBox(width: 8),
            const Text('Clientes'),
            const Spacer(),
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close, color: Colors.black),
            ),
          ],
        ),
        content: SizedBox(
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      style: const TextStyle(color: Colors.black),
                      decoration: InputDecoration(
                        hintText: 'Buscar cliente...',
                        hintStyle: TextStyle(color: Colors.black54),
                        prefixIcon: Icon(
                          Icons.search,
                          size: 20,
                          color: Colors.black,
                        ),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(
                      Icons.person_add_alt_1_outlined,
                      color: Colors.black,
                    ),
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
                              color: Colors.black38,
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'No se encontraron clientes',
                              style: TextStyle(color: Colors.black54),
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
                              color: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(color: Colors.grey.shade300),
                              ),
                              child: ListTile(
                                dense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 4,
                                ),
                                leading: CircleAvatar(
                                  radius: 18,
                                  backgroundColor: Colors.grey.shade200,
                                  child: Text(
                                    client.nombre[0].toUpperCase(),
                                    style: const TextStyle(
                                      color: Colors.black,
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
                                    color: Colors.black,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  client.telefono ?? 'Sin telefono',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.black54,
                                  ),
                                ),
                                trailing: const Icon(
                                  Icons.arrow_forward_ios,
                                  size: 14,
                                  color: Colors.black54,
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
