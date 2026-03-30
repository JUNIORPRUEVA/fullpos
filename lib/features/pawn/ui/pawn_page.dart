import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../clients/data/client_model.dart';
import '../../clients/data/clients_repository.dart';
import '../data/pawn_model.dart';
import '../data/pawn_repository.dart';
import 'pawn_form_dialog.dart';

/// Pantalla de empeño
class PawnPage extends StatefulWidget {
  const PawnPage({super.key});

  @override
  State<PawnPage> createState() => _PawnPageState();
}

class _PawnPageState extends State<PawnPage> {
  final _currency = NumberFormat('#,##0.00', 'en_US');
  final _date = DateFormat('dd/MM/yyyy');

  List<PawnModel> _pawns = [];
  Map<int, ClientModel> _clientsById = {};
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    final results = await Future.wait([
      PawnRepository.getAll(),
      ClientsRepository.getAll(),
    ]);

    if (!mounted) return;
    final pawns = results[0] as List<PawnModel>;
    final clients = results[1] as List<ClientModel>;

    setState(() {
      _pawns = pawns..sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));
      _clientsById = {
        for (final client in clients)
          if (client.id != null) client.id!: client,
      };
      _isLoading = false;
    });
  }

  Future<void> _openPawnDialog([PawnModel? pawn]) async {
    final result = await showDialog<PawnModel>(
      context: context,
      builder: (context) => PawnFormDialog(pawn: pawn),
    );

    if (result == null) return;
    await _loadData();
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          pawn == null
              ? 'Empeño registrado exitosamente'
              : 'Empeño actualizado exitosamente',
        ),
        backgroundColor: AppColors.success,
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'cerrado':
        return AppColors.textMuted;
      case 'renovado':
        return AppColors.warning;
      default:
        return AppColors.success;
    }
  }

  String _money(double value) => '4 ${_currency.format(value)}';

  Widget _buildMetricCard({
    required IconData icon,
    required String label,
    required String value,
    required Color tone,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(AppSizes.paddingM),
        decoration: BoxDecoration(
          color: AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(AppSizes.radiusL),
          border: Border.all(color: AppColors.surfaceLightBorder),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: tone.withOpacity(0.12),
                borderRadius: BorderRadius.circular(AppSizes.radiusM),
              ),
              child: Icon(icon, color: tone),
            ),
            const SizedBox(width: AppSizes.spaceM),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: AppSizes.spaceXS),
                  Text(
                    value,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeCount = _pawns.where((pawn) => pawn.status == 'activo').length;
    final totalDelivered = _pawns.fold<double>(
      0,
      (sum, pawn) => sum + pawn.monto,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
              onPressed: _isLoading ? null : _openPawnDialog,
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
        Row(
          children: [
            _buildMetricCard(
              icon: Icons.inventory_2_outlined,
              label: 'Empeños registrados',
              value: '${_pawns.length}',
              tone: AppColors.gold,
            ),
            const SizedBox(width: AppSizes.spaceM),
            _buildMetricCard(
              icon: Icons.lock_clock_outlined,
              label: 'Activos',
              value: '$activeCount',
              tone: AppColors.warning,
            ),
            const SizedBox(width: AppSizes.spaceM),
            _buildMetricCard(
              icon: Icons.payments_outlined,
              label: 'Monto entregado',
              value: _money(totalDelivered),
              tone: AppColors.success,
            ),
          ],
        ),
        const SizedBox(height: AppSizes.spaceL),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(AppSizes.radiusXL),
              border: Border.all(color: AppColors.surfaceLightBorder),
            ),
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _pawns.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSizes.paddingXL),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.diamond_outlined,
                            size: 64,
                            color: AppColors.textMuted,
                          ),
                          const SizedBox(height: AppSizes.spaceM),
                          const Text(
                            'Aún no hay empeños registrados',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: AppSizes.spaceS),
                          const Text(
                            'Usa “Nuevo Empeño” para registrar la prenda, el cliente y el monto inicial.',
                            style: TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 16,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(AppSizes.paddingL),
                    itemCount: _pawns.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: AppSizes.spaceM),
                    itemBuilder: (context, index) {
                      final pawn = _pawns[index];
                      final client = _clientsById[pawn.clientId];
                      final tone = _statusColor(pawn.status);

                      return Container(
                        padding: const EdgeInsets.all(AppSizes.paddingM),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceLightVariant,
                          borderRadius: BorderRadius.circular(AppSizes.radiusL),
                          border: Border.all(
                            color: AppColors.surfaceLightBorder,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                color: tone.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(
                                  AppSizes.radiusL,
                                ),
                              ),
                              child: Icon(Icons.diamond, color: tone),
                            ),
                            const SizedBox(width: AppSizes.spaceM),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          pawn.descripcion,
                                          style: const TextStyle(
                                            color: AppColors.textPrimary,
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: AppSizes.paddingS,
                                          vertical: AppSizes.paddingXS,
                                        ),
                                        decoration: BoxDecoration(
                                          color: tone.withOpacity(0.12),
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                        ),
                                        child: Text(
                                          pawn.status.toUpperCase(),
                                          style: TextStyle(
                                            color: tone,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: AppSizes.spaceS),
                                  Text(
                                    client?.nombre ??
                                        'Cliente #${pawn.clientId}',
                                    style: const TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: AppSizes.spaceXS),
                                  Text(
                                    'Registrado el ${_date.format(DateTime.fromMillisecondsSinceEpoch(pawn.createdAtMs))}',
                                    style: const TextStyle(
                                      color: AppColors.textMuted,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: AppSizes.spaceM),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  _money(pawn.monto),
                                  style: const TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: AppSizes.spaceS),
                                TextButton.icon(
                                  onPressed: () => _openPawnDialog(pawn),
                                  icon: const Icon(
                                    Icons.edit_outlined,
                                    size: 18,
                                  ),
                                  label: const Text('Editar'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}
