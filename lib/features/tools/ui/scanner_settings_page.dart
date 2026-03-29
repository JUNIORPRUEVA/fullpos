import 'package:flutter/material.dart';

import '../../../core/security/security_config.dart'
    show SecurityConfig, SecurityConfigRepository;
import '../../../core/session/session_manager.dart';
import '../../settings/ui/settings_layout.dart';

/// Configuración del lector de códigos (ubicado en Herramientas)
class ScannerSettingsPage extends StatefulWidget {
  const ScannerSettingsPage({super.key});

  @override
  State<ScannerSettingsPage> createState() => _ScannerSettingsPageState();
}

class _ScannerSettingsPageState extends State<ScannerSettingsPage> {
  SecurityConfig? _config;
  bool _loading = true;
  bool _saving = false;
  bool _hasChanges = false;
  int _companyId = 1;
  String _terminalId = '';
  final _prefixController = TextEditingController();
  final _suffixController = TextEditingController();
  final _timeoutController = TextEditingController();

  @override
  void dispose() {
    _prefixController.dispose();
    _suffixController.dispose();
    _timeoutController.dispose();
    super.dispose();
  }

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
      _saving = false;
      _hasChanges = false;
    });
    _prefixController.text = config.scannerPrefix ?? '';
    _suffixController.text = config.scannerSuffix;
    _timeoutController.text = config.scannerTimeoutMs.toString();
  }

  Future<void> _save(SecurityConfig newConfig) async {
    if (!mounted) return;
    setState(() {
      _saving = true;
      _config = newConfig;
    });
    try {
      await SecurityConfigRepository.save(
        config: newConfig,
        companyId: _companyId,
        terminalId: _terminalId,
      );
      if (!mounted) return;
      setState(() {
        _hasChanges = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Configuración del lector guardada')),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _saveCurrentValues() async {
    final config = _config;
    if (config == null) return;
    final parsedTimeout = int.tryParse(_timeoutController.text.trim());
    final nextConfig = config.copyWith(
      scannerPrefix: _prefixController.text.trim().isEmpty
          ? null
          : _prefixController.text.trim(),
      scannerSuffix: _suffixController.text.isEmpty ? '\n' : _suffixController.text,
      scannerTimeoutMs: parsedTimeout == null || parsedTimeout <= 0
          ? config.scannerTimeoutMs
          : parsedTimeout,
    );
    _timeoutController.text = nextConfig.scannerTimeoutMs.toString();
    await _save(nextConfig);
  }

  void _markDirty() {
    if (!mounted) return;
    setState(() {
      _hasChanges = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _config == null) {
      return Theme(
        data: SettingsLayout.brandedTheme(context),
        child: const Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    final config = _config!;
    final scheme = Theme.of(context).colorScheme;

    return Theme(
      data: SettingsLayout.brandedTheme(context),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Lector / scanner'),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton.icon(
                onPressed: (_saving || !_hasChanges) ? null : _saveCurrentValues,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(_saving ? 'Guardando...' : 'Guardar'),
              ),
            ),
          ],
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            return SettingsLayout.pageFrame(
              constraints,
              child: ListView(
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: scheme.outlineVariant.withOpacity(0.4),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Terminal: $_terminalId',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 12),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Scanner habilitado'),
                          value: config.scannerEnabled,
                          onChanged: _saving
                              ? null
                              : (v) {
                                  setState(() {
                                    _config = config.copyWith(scannerEnabled: v);
                                    _hasChanges = true;
                                  });
                                },
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _prefixController,
                          decoration: const InputDecoration(
                            labelText: 'Prefijo (opcional)',
                          ),
                          onChanged: (_) => _markDirty(),
                          onFieldSubmitted: (_) => _saveCurrentValues(),
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: _suffixController,
                          decoration: const InputDecoration(
                            labelText: 'Sufijo (default Enter \\n)',
                          ),
                          onChanged: (_) => _markDirty(),
                          onFieldSubmitted: (_) => _saveCurrentValues(),
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: _timeoutController,
                          decoration: const InputDecoration(
                            labelText: 'Timeout agrupación (ms)',
                          ),
                          keyboardType: TextInputType.number,
                          onChanged: (_) => _markDirty(),
                          onFieldSubmitted: (_) => _saveCurrentValues(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
