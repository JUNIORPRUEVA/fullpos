import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Adds consistent desktop keyboard shortcuts for dialogs:
/// - `Esc` => close/cancel
/// - `Enter`/`NumpadEnter` => submit/confirm (if [onSubmit] provided)
///
/// Note: [onSubmit] should perform validation and close the dialog itself
/// (e.g. via `Navigator.pop`) only when successful.
class DialogKeyboardShortcuts extends StatelessWidget {
  final Widget child;
  final FutureOr<void> Function()? onSubmit;
  final VoidCallback? onCancel;

  const DialogKeyboardShortcuts({
    super.key,
    required this.child,
    this.onSubmit,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final submitAction = onSubmit ?? () => Navigator.of(context).maybePop();
    return Shortcuts(
      shortcuts: {
        const SingleActivator(LogicalKeyboardKey.escape): const DismissIntent(),
        const SingleActivator(LogicalKeyboardKey.enter): const ActivateIntent(),
        const SingleActivator(LogicalKeyboardKey.numpadEnter):
            const ActivateIntent(),
      },
      child: Actions(
        actions: {
          DismissIntent: CallbackAction<DismissIntent>(
            onInvoke: (_) {
              (onCancel ?? () => Navigator.of(context).maybePop())();
              return null;
            },
          ),
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              submitAction();
              return null;
            },
          ),
        },
        child: Focus(autofocus: true, child: child),
      ),
    );
  }
}
