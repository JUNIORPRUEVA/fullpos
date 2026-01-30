import 'package:flutter/material.dart';
import '../../data/ncf_book_model.dart';
import '../../../../core/ui/dialog_keyboard_shortcuts.dart';

class NcfPickerDialog extends StatefulWidget {
  final String ncfType;
  final List<NcfBookModel> availableNcfs;
  final VoidCallback? onCreateNew;

  const NcfPickerDialog({
    super.key,
    required this.ncfType,
    required this.availableNcfs,
    this.onCreateNew,
  });

  @override
  State<NcfPickerDialog> createState() => _NcfPickerDialogState();
}

class _NcfPickerDialogState extends State<NcfPickerDialog> {
  NcfBookModel? _selectedBook;

  @override
  Widget build(BuildContext context) {
    return DialogKeyboardShortcuts(
      onSubmit: () {
        if (_selectedBook != null) {
          Navigator.pop(context, _selectedBook);
        }
      },
      child: Dialog(
        child: Container(
          width: 400,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
            const Text('Seleccionar NCF', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            if (widget.availableNcfs.isEmpty)
              Column(
                children: [
                  const Text('No hay talonarios NCF disponibles.'),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Crear nuevo talonario'),
                    onPressed: widget.onCreateNew,
                  ),
                ],
              )
            else
              ...[
                DropdownButton<NcfBookModel>(
                  isExpanded: true,
                  value: _selectedBook,
                  hint: const Text('Selecciona un talonario'),
                  items: widget.availableNcfs.map((book) {
                    return DropdownMenuItem<NcfBookModel>(
                      value: book,
                      child: Text('${book.type} - ${book.series} (${book.nextN}/${book.toN})'),
                    );
                  }).toList(),
                  onChanged: (book) => setState(() => _selectedBook = book),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  icon: const Icon(Icons.check),
                  label: const Text('Seleccionar'),
                  onPressed: _selectedBook != null
                      ? () => Navigator.pop(context, _selectedBook)
                      : null,
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: widget.onCreateNew,
                  child: const Text('Crear nuevo talonario'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
