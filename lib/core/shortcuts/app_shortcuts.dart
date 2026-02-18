import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../errors/error_handler.dart';
import '../window/window_service.dart';

/// Wrapper de atajos de teclado globales para la aplicación
class AppShortcuts extends StatelessWidget {
  final Widget child;

  const AppShortcuts({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        // ESC: Cerrar diálogos / Navegar atrás
        const SingleActivator(LogicalKeyboardKey.escape): () {
          ErrorHandler.navigatorKey.currentState?.maybePop();
        },
        // ENTER / NUMPAD ENTER: confirmar acción cuando el foco está dentro de un diálogo
        const SingleActivator(LogicalKeyboardKey.enter): _activateDialogPrimary,
        const SingleActivator(LogicalKeyboardKey.numpadEnter):
            _activateDialogPrimary,

        // Ctrl+Q: Cerrar aplicación (con confirmación)
        const SingleActivator(LogicalKeyboardKey.keyQ, control: true): () {
          _showExitConfirmation();
        },
      },
      child: Focus(autofocus: true, child: child),
    );
  }

  void _activateDialogPrimary() {
    final focusNode = FocusManager.instance.primaryFocus;
    final focusContext = focusNode?.context;
    if (focusContext == null) return;

    final inDialog =
        focusContext.findAncestorWidgetOfExactType<Dialog>() != null ||
        focusContext.findAncestorWidgetOfExactType<AlertDialog>() != null;
    if (!inDialog) return;

    final editable = focusContext.findAncestorWidgetOfExactType<EditableText>();
    if (editable != null && (editable.maxLines == null || editable.maxLines! > 1)) {
      return;
    }

    Actions.maybeInvoke(focusContext, const ActivateIntent());
  }

  /// Mostrar confirmación antes de cerrar la aplicación
  void _showExitConfirmation() {
    final context = ErrorHandler.navigatorKey.currentContext;
    if (context == null) return;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cerrar Aplicación'),
        content: const Text('¿Está seguro que desea salir del sistema?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              WindowService.close();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Salir'),
          ),
        ],
      ),
    );
  }
}

/// Intents personalizados para acciones POS
class PosIntents {
  // Búsqueda
  static const focusSearchProduct = FocusSearchProductIntent();
  static const focusSearchClient = FocusSearchClientIntent();

  // Cliente
  static const newClient = NewClientIntent();

  // Carrito
  static const adjustStock = AdjustStockIntent();
  static const applyDiscount = ApplyDiscountIntent();
  static const switchMode = SwitchModeIntent();

  // Pago
  static const openPayment = OpenPaymentIntent();
  static const printReceipt = PrintReceiptIntent();
  static const finalizeSale = FinalizeSaleIntent();

  // Item seleccionado
  static const deleteSelectedItem = DeleteSelectedItemIntent();
  static const increaseQuantity = IncreaseQuantityIntent();
  static const decreaseQuantity = DecreaseQuantityIntent();
}

// Intent Classes
class FocusSearchProductIntent extends Intent {
  const FocusSearchProductIntent();
}

class FocusSearchClientIntent extends Intent {
  const FocusSearchClientIntent();
}

class NewClientIntent extends Intent {
  const NewClientIntent();
}

class AdjustStockIntent extends Intent {
  const AdjustStockIntent();
}

class ApplyDiscountIntent extends Intent {
  const ApplyDiscountIntent();
}

class SwitchModeIntent extends Intent {
  const SwitchModeIntent();
}

class OpenPaymentIntent extends Intent {
  const OpenPaymentIntent();
}

class PrintReceiptIntent extends Intent {
  const PrintReceiptIntent();
}

class FinalizeSaleIntent extends Intent {
  const FinalizeSaleIntent();
}

class DeleteSelectedItemIntent extends Intent {
  const DeleteSelectedItemIntent();
}

class IncreaseQuantityIntent extends Intent {
  const IncreaseQuantityIntent();
}

class DecreaseQuantityIntent extends Intent {
  const DecreaseQuantityIntent();
}
