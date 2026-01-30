// ignore_for_file: file_names

// EJEMPLO: Cómo usar el nuevo sistema de temas en tus módulos
//
// Este archivo muestra patrones de uso para diferentes escenarios
//
// ⚠️ NOTA: Este es un archivo de DOCUMENTACIÓN/EJEMPLO
// Los códigos aquí son ejemplos que puedes copiar en tus widgets reales.

/*
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ============================================================================
// EJEMPLO 1: Widget Simple (Sin State)
// ============================================================================

class VentasHomeWidget extends ConsumerWidget {
  const VentasHomeWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ✅ USAR Theme.of(context) para acceder a colores/estilos
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Título con estilo del tema
          Text(
            'Mis Ventas',
            style: Theme.of(context).textTheme.displaySmall,
          ),

          const SizedBox(height: 16),

          // Tarjeta que respeta el tema
          Card(
            // Color viene automáticamente del tema
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Esta tarjeta respeta el tema actual',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Botón que respeta el tema
          ElevatedButton(
            // Estilo viene automáticamente del tema
            onPressed: () {},
            child: Text(
              'Crear Venta',
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// EJEMPLO 2: Acceder al Tema Actual
// ============================================================================

class ThemeInfoWidget extends ConsumerWidget {
  const ThemeInfoWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ✅ Obtener el tema actual
    final currentTheme = ref.watch(appThemeProvider);

    return Column(
      children: [
        // Mostrar tema actual
        Text(
          'Tema: ${currentTheme.label}',
          style: Theme.of(context).textTheme.bodyMedium,
        ),

        const SizedBox(height: 12),

        // Lógica específica por tema
        if (currentTheme == AppThemeEnum.proPos)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withAlpha(25),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Optimizado para punto de venta',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),

        if (currentTheme == AppThemeEnum.azulBlancoNegro)
          Text(
            'Tema profesional y moderno',
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
    );
  }
}

// ============================================================================
// EJEMPLO 3: Cambiar Tema Dentro del Módulo
// ============================================================================

class PrestamosThemeSwitcherButton extends ConsumerWidget {
  const PrestamosThemeSwitcherButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeNotifier = ref.read(appThemeProvider.notifier);

    return PopupMenuButton<AppThemeEnum>(
      itemBuilder: (context) => [
        PopupMenuItem(
          value: AppThemeEnum.original,
          child: Row(
            children: [
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: AppColors.teal700,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              const Text('Tema Original'),
            ],
          ),
        ),
        PopupMenuItem(
          value: AppThemeEnum.azulBlancoNegro,
          child: Row(
            children: [
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: const Color(0xFF0052CC),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              const Text('Azul / Blanco'),
            ],
          ),
        ),
        PopupMenuItem(
          value: AppThemeEnum.proPos,
          child: Row(
            children: [
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: const Color(0xFF065F46),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              const Text('Pro POS'),
            ],
          ),
        ),
      ],
      onSelected: (theme) => themeNotifier.setTheme(theme),
      child: const Icon(Icons.palette),
    );
  }
}

// ============================================================================
// EJEMPLO 4: Componente Personalizado Que Respeta Tema
// ============================================================================

class VentaCardProfesional extends ConsumerWidget {
  final String clientName;
  final double amount;
  final VoidCallback onTap;

  const VentaCardProfesional({
    super.key,
    required this.clientName,
    required this.amount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      // ✅ Respeta Card theme automáticamente
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    clientName,
                    // ✅ Usa titleMedium del tema
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'RD\$ ${amount.toStringAsFixed(2)}',
                    // ✅ Usa bodySmall del tema
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              Icon(
                Icons.arrow_forward_ios,
                // ✅ Usa color primario del tema
                color: Theme.of(context).colorScheme.primary,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// EJEMPLO 5: Dialog Que Respeta Tema
// ============================================================================

Future<bool> mostrarConfirmacionVenta(BuildContext context) async {
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          // ✅ Los estilos respetan automáticamente el tema
          title: Text(
            '¿Confirmar venta?',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          content: Text(
            'Esta acción no se puede deshacer.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          actions: [
            OutlinedButton(
              // ✅ Respeta outlinedButtonTheme del tema
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              // ✅ Respeta elevatedButtonTheme del tema
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirmar'),
            ),
          ],
        ),
      ) ??
      false;
}

// ============================================================================
// EJEMPLO 6: ListTile Que Respeta Tema
// ============================================================================

class PrestamoPendienteListItem extends ConsumerWidget {
  final String clientName;
  final double amount;
  final DateTime dueDate;
  final VoidCallback onTap;

  const PrestamoPendienteListItem({
    super.key,
    required this.clientName,
    required this.amount,
    required this.dueDate,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ✅ Obtener tema para lógica específica
    final currentTheme = ref.watch(appThemeProvider);
    final isDaysOverdue =
        DateTime.now().isAfter(dueDate) ? DateTime.now().difference(dueDate).inDays : 0;

    return ListTile(
      // ✅ ListTile respeta el tema automáticamente
      onTap: onTap,
      leading: CircleAvatar(
        // ✅ Usar color primario del tema
        backgroundColor: Theme.of(context).colorScheme.primary,
        child: Icon(
          Icons.person,
          color: Theme.of(context).colorScheme.onPrimary,
        ),
      ),
      title: Text(
        clientName,
        style: Theme.of(context).textTheme.titleSmall,
      ),
      subtitle: Text(
        'RD\$ ${amount.toStringAsFixed(2)}',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          // ✅ Usar color secundario si está vencido
          color: isDaysOverdue > 0
              ? Theme.of(context).colorScheme.error.withAlpha(25)
              : Theme.of(context).colorScheme.secondary.withAlpha(25),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          isDaysOverdue > 0 ? '⚠️ Vencido' : '✓ Pendiente',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: isDaysOverdue > 0
                    ? Theme.of(context).colorScheme.error
                    : Theme.of(context).colorScheme.secondary,
              ),
        ),
      ),
    );
  }
}

// ============================================================================
// EJEMPLO 7: DataTable Que Respeta Tema
// ============================================================================

class VentasDataTable extends ConsumerWidget {
  final List<VentaModel> ventas;

  const VentasDataTable({
    super.key,
    required this.ventas,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DataTable(
      // ✅ DataTable respeta el tema automáticamente
      headingRowColor: MaterialStateProperty.all(
        // ✅ Usar color primario para header
        Theme.of(context).colorScheme.primary.withAlpha(25),
      ),
      columns: [
        DataColumn(
          label: Text(
            'Cliente',
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        DataColumn(
          label: Text(
            'Monto',
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        DataColumn(
          label: Text(
            'Fecha',
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
      ],
      rows: ventas
          .map(
            (venta) => DataRow(
              cells: [
                DataCell(
                  Text(
                    venta.clientName,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                DataCell(
                  Text(
                    'RD\$ ${venta.amount}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                  ),
                ),
                DataCell(
                  Text(
                    '${venta.date.day}/${venta.date.month}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          )
          .toList(),
    );
  }
}

// ============================================================================
// EJEMPLO 8: Form Que Respeta Tema
// ============================================================================

class VentaFormWidget extends ConsumerStatefulWidget {
  final Function(VentaModel) onSubmit;

  const VentaFormWidget({
    super.key,
    required this.onSubmit,
  });

  @override
  ConsumerState<VentaFormWidget> createState() => _VentaFormWidgetState();
}

class _VentaFormWidgetState extends ConsumerState<VentaFormWidget> {
  final _formKey = GlobalKey<FormState>();
  final _clientController = TextEditingController();
  final _amountController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          // ✅ TextFormField respeta inputDecorationTheme automáticamente
          TextFormField(
            controller: _clientController,
            decoration: InputDecoration(
              labelText: 'Cliente',
              // ✅ Estilos del tema se aplican automáticamente
              hintText: 'Nombre del cliente',
            ),
            validator: (value) {
              if (value?.isEmpty ?? true) {
                return 'Campo requerido';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _amountController,
            decoration: InputDecoration(
              labelText: 'Monto',
              hintText: '0.00',
            ),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 24),
          // ✅ Botón respeta elevatedButtonTheme del tema
          ElevatedButton(
            onPressed: () {
              if (_formKey.currentState!.validate()) {
                // ... procesar
              }
            },
            child: const Text('Guardar Venta'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _clientController.dispose();
    _amountController.dispose();
    super.dispose();
  }
}

// ============================================================================
// RESUMEN: LO QUE DEBES HACER
// ============================================================================

/*
✅ REGLA DE ORO:

   NUNCA hardcodees colores ni estilos.
   SIEMPRE usa Theme.of(context).

✅ EJEMPLOS CORRECTOS:

   // Colores
   color: Theme.of(context).colorScheme.primary
   color: Theme.of(context).colorScheme.secondary
   color: Theme.of(context).colorScheme.error
   
   // Textos
   style: Theme.of(context).textTheme.titleLarge
   style: Theme.of(context).textTheme.bodyMedium
   style: Theme.of(context).textTheme.labelSmall

   // Fondos
   color: Theme.of(context).scaffoldBackgroundColor
   color: Theme.of(context).colorScheme.surface
   
   // AppBar (automático)
   backgroundColor: Theme.of(context).appBarTheme.backgroundColor

❌ EJEMPLOS INCORRECTOS (NUNCA HACER):

   color: Color(0xFF00796B)  // ❌ NUNCA
   color: AppColors.teal700  // ❌ NUNCA (usa theme en su lugar)
   style: TextStyle(color: Colors.black)  // ❌ NUNCA
   backgroundColor: Colors.white  // ❌ NUNCA

✅ PATRÓN A SEGUIR EN CADA WIDGET:

   class MiWidget extends ConsumerWidget {
     @override
     Widget build(BuildContext context, WidgetRef ref) {
       // 1. Si necesitas el tema actual
       final currentTheme = ref.watch(appThemeProvider);
       
       // 2. Usar Theme.of(context) para colores/estilos
       return Container(
         color: Theme.of(context).scaffoldBackgroundColor,
         child: Text(
           'Contenido',
           style: Theme.of(context).textTheme.bodyMedium,
         ),
       );
     }
   }

✅ PARA CAMBIAR TEMA:

   final notifier = ref.read(appThemeProvider.notifier);
   await notifier.setTheme(AppThemeEnum.proPos);

*/

// ============================================================================
// FIN DE EJEMPLOS
// ============================================================================

/// Modelo de ejemplo (para las demostraciones arriba)
class VentaModel {
  final String clientName;
  final double amount;
  final DateTime date;

  VentaModel({
    required this.clientName,
    required this.amount,
    required this.date,
  });
}

// Imports necesarios para los ejemplos:
/*
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
*/
import '../../../core/providers/theme_provider.dart';
import '../../../core/theme/app_themes.dart';
import '../../../core/constants/app_colors.dart';  // Si lo necesitas
*/
