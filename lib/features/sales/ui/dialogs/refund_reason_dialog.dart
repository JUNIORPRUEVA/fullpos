import 'package:flutter/material.dart';

/// Diálogo en dos pasos: (1) Confirmar acción peligrosa, (2) Motivo obligatorio.
Future<String?> showRefundReasonDialog(BuildContext context) async {
  // Paso 1: Confirmación
  final confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      return AlertDialog(
        title: const Text('Acción peligrosa: Reembolso'),
        content: const Text(
          '¿Está seguro que desea realizar el reembolso? Esta acción afecta caja y stock.',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('No'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sí, continuar'),
          ),
        ],
      );
    },
  );

  if (confirmed != true) return null;

  // Paso 2: Motivo obligatorio
  final TextEditingController controller = TextEditingController();
  String? errorText;

  final reason = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Motivo del reembolso'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Ingrese el motivo del reembolso (obligatorio).'),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  autofocus: true,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: 'Motivo',
                    errorText: errorText,
                  ),
                  onChanged: (_) {
                    if (errorText != null) setState(() => errorText = null);
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () {
                  final text = controller.text.trim();
                  if (text.isEmpty) {
                    setState(() => errorText = 'El motivo es obligatorio');
                  } else {
                    Navigator.of(context).pop(text);
                  }
                },
                child: const Text('Guardar motivo'),
              ),
            ],
          );
        },
      );
    },
  );

  controller.dispose();
  return reason;
}
