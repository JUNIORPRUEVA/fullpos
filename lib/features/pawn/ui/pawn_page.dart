import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';

/// Pantalla de empeño
class PawnPage extends StatelessWidget {
  const PawnPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Encabezado
        Row(
          children: [
            const Icon(Icons.diamond, size: 32, color: AppColors.gold),
            const SizedBox(width: AppSizes.spaceM),
            const Text(
              'Gestión de Empeño',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            ElevatedButton.icon(
              onPressed: () {
                // TODO: Abrir formulario de nuevo empeño
              },
              icon: const Icon(Icons.add),
              label: const Text('Nuevo Empeño'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: AppColors.bgDark,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSizes.spaceL),

        // Contenido
        Expanded(
          child: Card(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.diamond_outlined,
                    size: 64,
                    color: AppColors.textMuted,
                  ),
                  const SizedBox(height: AppSizes.spaceM),
                  Text(
                    'Módulo de Empeño',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: AppSizes.spaceS),
                  Text(
                    'TODO: Implementar gestión de empeños',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 16),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
