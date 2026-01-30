import 'package:flutter/material.dart';

import '../../../core/security/security_config.dart'
    show SecurityConfig, SecurityConfigRepository;
import '../../../core/session/session_manager.dart';

/// Configuración del lector de códigos (ubicado en Herramientas)
class ScannerSettingsPage extends StatefulWidget {
  const ScannerSettingsPage({super.key});

  @override
  State<ScannerSettingsPage> createState() => _ScannerSettingsPageState();
}

class _ScannerSettingsPageState extends State<ScannerSettingsPage> {
  SecurityConfig? _config;
  bool _loading = true;
  int _companyId = 1;
  String _terminalId = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final companyId = await SessionManager.companyId() ?? 1;
    final terminalId =
        await SessionManager.terminalId() ??
        await SessionManager.ensureTerminalId();
    final config = await SecurityConfigRepository.load(
      companyId: companyId,
      terminalId: terminalId,
    );

    if (!mounted) return;
    setState(() {
      _config = config;
      _companyId = companyId;
      _terminalId = terminalId;
      _loading = false;
    });
  }

  Future<void> _save(SecurityConfig newConfig) async {
    if (!mounted) return;
    setState(() {
      _config = newConfig;
    });
    await SecurityConfigRepository.save(
      config: newConfig,
      companyId: _companyId,
      terminalId: _terminalId,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _config == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final config = _config!;

    return Scaffold(
      appBar: AppBar(title: const Text('Configuración del lector')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Terminal: $_terminalId',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            title: const Text('Scanner habilitado'),
            subtitle: const Text(
              'Activar/desactivar lector para esta terminal',
            ),
            value: config.scannerEnabled,
            onChanged: (v) => _save(config.copyWith(scannerEnabled: v)),
          ),
          TextField(
            decoration: const InputDecoration(labelText: 'Prefijo (opcional)'),
            controller: TextEditingController(text: config.scannerPrefix ?? ''),
            onSubmitted: (value) => _save(
              config.copyWith(
                scannerPrefix: value.trim().isEmpty ? null : value,
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            decoration: const InputDecoration(
              labelText: 'Sufijo (default Enter \\n)',
            ),
            controller: TextEditingController(text: config.scannerSuffix),
            onSubmitted: (value) => _save(
              config.copyWith(scannerSuffix: value.isEmpty ? '\n' : value),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            decoration: const InputDecoration(
              labelText: 'Timeout agrupación (ms)',
            ),
            keyboardType: TextInputType.number,
            controller: TextEditingController(
              text: config.scannerTimeoutMs.toString(),
            ),
            onSubmitted: (value) {
              final parsed =
                  int.tryParse(value.trim()) ?? config.scannerTimeoutMs;
              _save(config.copyWith(scannerTimeoutMs: parsed));
            },
          ),
          const SizedBox(height: 16),
          const Text(
            'Consejo: Ajusta prefijo/sufijo según tu lector (ej. \\n o \\t) para facilitar el ingreso en formularios.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
