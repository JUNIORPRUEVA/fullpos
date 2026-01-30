import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/db_hardening/db_hardening.dart';
import '../../../core/errors/error_handler.dart';
import '../data/models/ncf_book_model.dart';
import '../data/ncf_repository.dart';
import 'dialogs/ncf_form_dialog.dart';

/// Página de gestión de NCF (Comprobantes Fiscales)
class NcfPage extends StatefulWidget {
  const NcfPage({super.key});

  @override
  State<NcfPage> createState() => _NcfPageState();
}

class _NcfPageState extends State<NcfPage> {
  final _ncfRepo = NcfRepository();
  List<NcfBookModel> _books = [];
  bool _isLoading = true;
  String _filter = 'all'; // all, active, inactive
  int _loadSeq = 0;

  @override
  void initState() {
    super.initState();
    _loadBooks();
  }

  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  Future<void> _loadBooks() async {
    if (!mounted) return;
    final seq = ++_loadSeq;
    _safeSetState(() => _isLoading = true);

    try {
      final books = await DbHardening.instance.runDbSafe<List<NcfBookModel>>(
        () => _ncfRepo.getAll(
          activeOnly: _filter == 'active'
              ? true
              : _filter == 'inactive'
              ? false
              : null,
        ),
        stage: 'tools/ncf/load',
      );
      if (!mounted || seq != _loadSeq) return;
      _safeSetState(() => _books = books);
    } catch (e, st) {
      if (!mounted || seq != _loadSeq) return;
      await ErrorHandler.instance.handle(
        e,
        stackTrace: st,
        context: context,
        onRetry: _loadBooks,
        module: 'tools/ncf/load',
      );
    } finally {
      if (mounted && seq == _loadSeq) {
        _safeSetState(() => _isLoading = false);
      }
    }
  }

  Future<void> _showForm([NcfBookModel? book]) async {
    final result = await showDialog<NcfBookModel>(
      context: context,
      builder: (context) => NcfFormDialog(ncfBook: book),
    );

    if (!mounted) return;
    if (result == null) return;

    try {
      if (book == null) {
        await _ncfRepo.create(result);
        if (!mounted) return;
        final scheme = Theme.of(context).colorScheme;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'NCF creado exitosamente',
              style: TextStyle(color: scheme.onPrimary),
            ),
            backgroundColor: scheme.primary,
          ),
        );
      } else {
        await _ncfRepo.update(result);
        if (!mounted) return;
        final scheme = Theme.of(context).colorScheme;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'NCF actualizado exitosamente',
              style: TextStyle(color: scheme.onPrimary),
            ),
            backgroundColor: scheme.primary,
          ),
        );
      }
      if (mounted) _loadBooks();
    } catch (e, st) {
      if (mounted) {
        await ErrorHandler.instance.handle(
          e,
          stackTrace: st,
          context: context,
          onRetry: () => _showForm(book),
          module: 'tools/ncf/save',
        );
      }
    }
  }

  Future<void> _toggleActive(NcfBookModel book) async {
    try {
      await _ncfRepo.toggleActive(book.id!);
      if (!mounted) return;
      final scheme = Theme.of(context).colorScheme;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(book.isActive ? 'NCF desactivado' : 'NCF activado'),
          backgroundColor: scheme.primary,
        ),
      );
      if (mounted) _loadBooks();
    } catch (e, st) {
      if (mounted) {
        await ErrorHandler.instance.handle(
          e,
          stackTrace: st,
          context: context,
          onRetry: () => _toggleActive(book),
          module: 'tools/ncf/toggle',
        );
      }
    }
  }

  Future<void> _delete(NcfBookModel book) async {
    final scheme = Theme.of(context).colorScheme;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar Eliminación'),
        content: Text(
          '¿Eliminar el talonario ${book.type}${book.series ?? ''} '
          '(${book.fromN}-${book.toN})?\n\n'
          'Esta acción no se puede deshacer si ya se han emitido NCF de este talonario.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: scheme.error),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (confirm != true) return;

    try {
      await _ncfRepo.delete(book.id!);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'NCF eliminado exitosamente',
            style: TextStyle(color: scheme.onPrimary),
          ),
          backgroundColor: scheme.primary,
        ),
      );
      if (mounted) _loadBooks();
    } catch (e, st) {
      if (mounted) {
        await ErrorHandler.instance.handle(
          e,
          stackTrace: st,
          context: context,
          onRetry: () => _delete(book),
          module: 'tools/ncf/delete',
        );
      }
    }
  }

  Color _getStatusColor(NcfBookModel book) {
    final scheme = Theme.of(context).colorScheme;
    if (!book.isActive) return Colors.grey;
    if (book.isExhausted) return scheme.error;
    if (book.expiresAt != null && book.expiresAt!.isBefore(DateTime.now())) {
      return Colors.orange;
    }
    return scheme.primary;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final horizontalPadding = (width * 0.04).clamp(12.0, 28.0);
          final verticalPadding = (width * 0.02).clamp(10.0, 20.0);

          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1400),
              child: Column(
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      verticalPadding,
                      horizontalPadding,
                      8,
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: scheme.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: scheme.outlineVariant.withOpacity(0.35),
                        ),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              IconButton(
                                icon: Icon(
                                  Icons.arrow_back,
                                  color: scheme.onSurface,
                                ),
                                onPressed: () => context.go('/tools'),
                              ),
                              const SizedBox(width: 10),
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: scheme.primaryContainer.withOpacity(
                                    0.65,
                                  ),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: scheme.outlineVariant.withOpacity(
                                      0.30,
                                    ),
                                  ),
                                ),
                                child: Icon(
                                  Icons.description,
                                  size: 22,
                                  color: scheme.onPrimaryContainer,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'NCF (Comprobantes Fiscales)',
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Gestión de talonarios de comprobantes',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: scheme.onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              FilledButton.icon(
                                onPressed: () => _showForm(),
                                icon: const Icon(Icons.add),
                                label: const Text('Nuevo'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              _FilterChip(
                                label: 'Todos',
                                isSelected: _filter == 'all',
                                onTap: () {
                                  setState(() => _filter = 'all');
                                  _loadBooks();
                                },
                              ),
                              const SizedBox(width: 10),
                              _FilterChip(
                                label: 'Activos',
                                isSelected: _filter == 'active',
                                onTap: () {
                                  setState(() => _filter = 'active');
                                  _loadBooks();
                                },
                              ),
                              const SizedBox(width: 10),
                              _FilterChip(
                                label: 'Inactivos',
                                isSelected: _filter == 'inactive',
                                onTap: () {
                                  setState(() => _filter = 'inactive');
                                  _loadBooks();
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: _isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : _books.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.description_outlined,
                                  size: 64,
                                  color: scheme.onSurfaceVariant.withOpacity(
                                    0.55,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'No hay talonarios de NCF',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                TextButton.icon(
                                  onPressed: () => _showForm(),
                                  icon: const Icon(Icons.add),
                                  label: const Text('Crear el primero'),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: EdgeInsets.fromLTRB(
                              horizontalPadding,
                              8,
                              horizontalPadding,
                              verticalPadding,
                            ),
                            itemCount: _books.length,
                            itemBuilder: (context, index) {
                              final book = _books[index];
                              return _NcfCard(
                                book: book,
                                statusColor: _getStatusColor(book),
                                onEdit: () => _showForm(book),
                                onToggleActive: () => _toggleActive(book),
                                onDelete: () => _delete(book),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? scheme.primary
              : scheme.surfaceVariant.withOpacity(0.55),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: scheme.outlineVariant.withOpacity(0.35)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: isSelected ? scheme.onPrimary : scheme.onSurface,
          ),
        ),
      ),
    );
  }
}

class _NcfCard extends StatelessWidget {
  final NcfBookModel book;
  final Color statusColor;
  final VoidCallback onEdit;
  final VoidCallback onToggleActive;
  final VoidCallback onDelete;

  const _NcfCard({
    required this.book,
    required this.statusColor,
    required this.onEdit,
    required this.onToggleActive,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final cardBg = Color.alphaBlend(
      statusColor.withOpacity(isDark ? 0.10 : 0.06),
      scheme.surface,
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: cardBg,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: scheme.outlineVariant.withOpacity(0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // Indicador de estado
            Container(
              width: 4,
              height: 60,
              decoration: BoxDecoration(
                color: statusColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 12),

            // Información principal
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer.withOpacity(0.75),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${book.type}${book.series ?? ''}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: scheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        NcfTypes.getDescription(book.type),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Rango: ${book.fromN} - ${book.toN}',
                    style: TextStyle(
                      fontSize: 13,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),

            // Próximo número
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Próximo',
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    book.nextN.toString(),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: scheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),

            // Disponibles
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Disponibles',
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    book.availableCount.toString(),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                    ),
                  ),
                ],
              ),
            ),

            // Estado
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      book.statusLabel,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: statusColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Acciones
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, color: scheme.onSurface),
              onSelected: (value) {
                switch (value) {
                  case 'edit':
                    onEdit();
                    break;
                  case 'toggle':
                    onToggleActive();
                    break;
                  case 'delete':
                    onDelete();
                    break;
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(Icons.edit, size: 18),
                      SizedBox(width: 8),
                      Text('Editar'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'toggle',
                  child: Row(
                    children: [
                      Icon(
                        book.isActive ? Icons.block : Icons.check_circle,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(book.isActive ? 'Desactivar' : 'Activar'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete, size: 18, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Eliminar', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
