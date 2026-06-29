import 'package:flutter/material.dart';

import 'app_recovery.dart';

class RecoveryScreen extends StatelessWidget {
  const RecoveryScreen({super.key, this.state});

  final AppRecoveryState? state;

  @override
  Widget build(BuildContext context) {
    final recovery = state ?? AppRecoveryController.instance.state;
    final isDb = recovery.kind == AppRecoveryKind.database;
    final title = isDb ? 'Recuperación de base de datos' : 'Reactivar terminal';
    final message = isDb
        ? 'FullPOS detectó una instalación previa y detuvo el arranque para proteger los datos.'
        : 'FullPOS no pudo recuperar la identidad local de esta instalación.';

    return Scaffold(
      backgroundColor: const Color(0xFFF2F6F9),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFD8E2EA)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x14000000),
                      blurRadius: 18,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        isDb
                            ? Icons.storage_outlined
                            : Icons.verified_user_outlined,
                        size: 34,
                        color: const Color(0xFF0F4C81),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        title,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        message,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'No se generó un terminal nuevo ni se modificó la licencia. Contacta soporte para continuar con una recuperación controlada.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      if ((recovery.reason ?? '').isNotEmpty) ...[
                        const SizedBox(height: 18),
                        SelectableText(
                          'Código técnico: ${recovery.reason}',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: const Color(0xFF506070)),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
