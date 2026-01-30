import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_loading_provider.dart';
import '../widgets/branded_loading_view.dart';

class AppLoadingOverlay extends ConsumerWidget {
  final Widget child;
  final String message;

  const AppLoadingOverlay({
    super.key,
    required this.child,
    this.message = 'Cargando...',
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLoading = ref.watch(appIsLoadingProvider);
    final scheme = Theme.of(context).colorScheme;

    return Stack(
      children: [
        child,
        if (isLoading)
          Positioned.fill(
            child: AbsorbPointer(
              absorbing: true,
              child: Container(
                color: scheme.scrim.withOpacity(0.72),
                child: BrandedLoadingView(message: message, fullScreen: false),
              ),
            ),
          ),
      ],
    );
  }
}
