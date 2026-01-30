import 'package:flutter/material.dart';
import '../../../../core/ui/dialog_keyboard_shortcuts.dart';

class TicketRenameDialog extends StatefulWidget {
  final String currentName;
  final bool isNewTicket;

  const TicketRenameDialog({
    super.key,
    required this.currentName,
    this.isNewTicket = false,
  });

  @override
  State<TicketRenameDialog> createState() => _TicketRenameDialogState();
}

class _TicketRenameDialogState extends State<TicketRenameDialog> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentName);
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.currentName.length,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.isNewTicket ? 'Nuevo Ticket' : 'Renombrar Ticket';
    final icon = widget.isNewTicket ? Icons.add_circle : Icons.edit;
    final screenSize = MediaQuery.of(context).size;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return DialogKeyboardShortcuts(
      onSubmit: _saveAndClose,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        insetPadding: EdgeInsets.symmetric(
          horizontal: screenSize.width * 0.1,
          vertical: screenSize.height * 0.15,
        ),
        child: Container(
          constraints: BoxConstraints(
            maxWidth: screenSize.width * 0.85,
            maxHeight: screenSize.height * 0.5,
          ),
          width: screenSize.width > 500 ? 420 : screenSize.width * 0.85,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
              // Header
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: screenSize.width * 0.04,
                  vertical: screenSize.height * 0.02,
                ),
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(icon, color: scheme.onPrimary, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: scheme.onPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, color: scheme.onPrimary),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              // Body
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: screenSize.width * 0.04,
                  vertical: screenSize.height * 0.02,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.isNewTicket
                          ? 'Ingresa un nombre para identificar este ticket:'
                          : 'Nombre del ticket:',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _controller,
                      autofocus: true,
                      maxLength: 100,
                      decoration: InputDecoration(
                        hintText: 'Ej: Mesa 5, Cliente Juan',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        prefixIcon: const Icon(Icons.label_outline, size: 20),
                        isDense: true,
                      ),
                      onSubmitted: (_) => _saveAndClose(),
                    ),
                    if (widget.isNewTicket)
                      Text(
                        'Puedes dejarlo vacío para usar el nombre por defecto',
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurface.withOpacity(0.6),
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                  ],
                ),
              ),
              // Footer
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: screenSize.width * 0.04,
                  vertical: screenSize.height * 0.015,
                ),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(16),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                      ),
                      child: const Text(
                        'Cancelar',
                        style: TextStyle(fontSize: 14),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _saveAndClose,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                      ),
                      child: const Text(
                        'Guardar',
                        style: TextStyle(fontSize: 14),
                      ),
                    ),
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

  void _saveAndClose() {
    final newName = _controller.text.trim();
    if (newName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('El nombre no puede estar vacío'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }
    Navigator.of(context).pop(newName);
  }
}
