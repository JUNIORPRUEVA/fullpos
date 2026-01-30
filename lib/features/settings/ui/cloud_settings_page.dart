import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/business_settings_model.dart';
import '../providers/business_settings_provider.dart';
import 'settings_layout.dart';

class CloudSettingsPage extends ConsumerStatefulWidget {
  const CloudSettingsPage({super.key});

  @override
  ConsumerState<CloudSettingsPage> createState() => _CloudSettingsPageState();
}

class _CloudSettingsPageState extends ConsumerState<CloudSettingsPage> {
  final _formKey = GlobalKey<FormState>();
  late BusinessSettings _settings;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final settings = ref.read(businessSettingsProvider);
      _settings = settings;
      setState(() => _loading = false);
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _save() async {
    final notifier = ref.read(businessSettingsProvider.notifier);
    final updated = _settings.copyWith(cloudEnabled: _settings.cloudEnabled);
    await notifier.saveSettings(updated);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Configuración de nube guardada')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nube y Accesos'),
        actions: [
          TextButton.icon(
            onPressed: _save,
            style: TextButton.styleFrom(foregroundColor: scheme.onPrimary),
            icon: const Icon(Icons.save),
            label: const Text('Guardar'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final padding = SettingsLayout.contentPadding(constraints);
            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: SettingsLayout.maxWidth(constraints),
                child: ListView(
                  padding: padding,
                  children: [
            SwitchListTile(
              title: const Text('Sincronización en la nube'),
              subtitle: const Text('Habilita el acceso a la app FULLPOS Owner'),
              value: _settings.cloudEnabled,
              onChanged: (v) {
                setState(() => _settings = _settings.copyWith(cloudEnabled: v));
              },
            ),
            const SizedBox(height: 12),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'FULLPOS Owner',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Costo: \$15 USD por usuario/mes. Para activar la nube y obtener la app FULLPOS Owner, escribe a soporte.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'Accesos a la nube',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Los accesos para FULLPOS Owner se crean desde Usuarios en el POS. Solo usuarios con rol Admin pueden iniciar sesión en la app Owner.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save),
              label: const Text('Guardar'),
            ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
