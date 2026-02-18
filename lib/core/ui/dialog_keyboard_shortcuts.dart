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
  final bool enableSubmitShortcuts;
  final bool enableDismissShortcut;
  final Map<ShortcutActivator, Intent>? extraShortcuts;
  final Map<Type, Action<Intent>>? extraActions;

  const DialogKeyboardShortcuts({
    super.key,
    required this.child,
    this.onSubmit,
    this.onCancel,
    this.enableSubmitShortcuts = true,
    this.enableDismissShortcut = true,
    this.extraShortcuts,
    this.extraActions,
  });

  @override
  Widget build(BuildContext context) {
    final submitAction = onSubmit ?? () => Navigator.of(context).maybePop();
    final shortcuts = <ShortcutActivator, Intent>{
      if (enableDismissShortcut)
        const SingleActivator(LogicalKeyboardKey.escape): const DismissIntent(),
      if (enableSubmitShortcuts)
        const SingleActivator(LogicalKeyboardKey.enter): const ActivateIntent(),
      if (enableSubmitShortcuts)
        const SingleActivator(LogicalKeyboardKey.numpadEnter):
            const ActivateIntent(),
      ...?extraShortcuts,
    };

    final actions = <Type, Action<Intent>>{
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
      ...?extraActions,
    };

    return Shortcuts(
      shortcuts: shortcuts,
      child: Actions(
        actions: actions,
        child: Focus(autofocus: true, child: child),
      ),
    );
  }
}
