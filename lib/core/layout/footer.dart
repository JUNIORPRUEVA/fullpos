import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_sizes.dart';
import '../session/session_manager.dart';
import 'footer_ticket_controller.dart';

/// Footer principal del layout.
///
/// En ventas muestra la barra inferior de ventas abiertas estilo POS.
/// En el resto de la app conserva una franja simple con nombre de empresa.
class Footer extends ConsumerStatefulWidget {
  const Footer({super.key, this.scale = 1.0});

  final double scale;

  @override
  ConsumerState<Footer> createState() => _FooterState();
}

class _FooterState extends ConsumerState<Footer> {
  String _userLabel = 'Usuario';

  @override
  void initState() {
    super.initState();
    _loadUserLabel();
  }

  Future<void> _loadUserLabel() async {
    final displayName = (await SessionManager.displayName())?.trim();
    final username = (await SessionManager.username())?.trim();
    if (!mounted) return;
    setState(() {
      _userLabel = (displayName != null && displayName.isNotEmpty)
          ? displayName
          : ((username != null && username.isNotEmpty) ? username : 'Usuario');
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(footerTicketControllerProvider);
    final tabs = controller.tabs;
    if (tabs.isNotEmpty) {
      return _SalesTicketsFooter(
        scale: widget.scale,
        userLabel: _userLabel,
        tabs: tabs,
        controller: controller,
      );
    }

    return Container(
      height: AppSizes.footerHeight,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.centerLeft,
      child: Text(
        _userLabel,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Color(0xFF64748B),
          fontSize: 12,
          fontWeight: FontWeight.w600,
          height: 1,
        ),
      ),
    );
  }
}

class _SalesTicketsFooter extends StatelessWidget {
  const _SalesTicketsFooter({
    required this.scale,
    required this.userLabel,
    required this.tabs,
    required this.controller,
  });

  final double scale;
  final String userLabel;
  final List<FooterTicketTabData> tabs;
  final FooterTicketController controller;

  @override
  Widget build(BuildContext context) {
    final s = scale.clamp(0.9, 1.05);
    final tabHeight = (AppSizes.footerHeight * s).clamp(30.0, 34.0);

    return Container(
      height: tabHeight,
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        border: Border(top: BorderSide(color: Color(0xFFD7E0EA))),
      ),
      child: Row(
        children: [
          Container(
            width: 148,
            height: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(
                right: BorderSide(color: Color(0xFFD7E0EA)),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.person_outline_rounded,
                  size: 14,
                  color: Color(0xFF14B8A6),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    userLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF475569),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.zero,
              itemCount: tabs.length + 1,
              itemBuilder: (context, index) {
                if (index == tabs.length) {
                  return _FooterAddButton(onTap: controller.add);
                }

                final tab = tabs[index];
                return _FooterSaleTab(
                  label: tab.label,
                  isActive: tab.isActive,
                  showAlertDot: tab.showAlertDot,
                  showDelete: tab.canDelete,
                  onTap: () => controller.select(index),
                  onRename: () => controller.rename(index),
                  onDelete: tab.canDelete ? () => controller.delete(index) : null,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FooterSaleTab extends StatelessWidget {
  const _FooterSaleTab({
    required this.label,
    required this.isActive,
    required this.showAlertDot,
    required this.showDelete,
    required this.onTap,
    required this.onRename,
    this.onDelete,
  });

  final String label;
  final bool isActive;
  final bool showAlertDot;
  final bool showDelete;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final foreground = isActive
        ? const Color(0xFF0F172A)
        : const Color(0xFF334155);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minWidth: 120, maxWidth: 156),
          decoration: BoxDecoration(
            color: isActive ? Colors.white : const Color(0xFFF1F5F9),
            border: const Border(
              right: BorderSide(color: Color(0xFFD7E0EA)),
            ),
            boxShadow: isActive
                ? const [
                    BoxShadow(
                      color: Color(0x0D1A56DB),
                      blurRadius: 8,
                      offset: Offset(0, -1),
                    ),
                  ]
                : null,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              const Icon(
                Icons.shopping_bag_outlined,
                size: 14,
                color: Color(0xFF334155),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: foreground,
                          fontSize: 12,
                          fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                          height: 1,
                        ),
                      ),
                    ),
                    if (showAlertDot)
                      const Positioned(
                        right: -2,
                        top: 3,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Color(0xFFEF4444),
                            shape: BoxShape.circle,
                          ),
                          child: SizedBox(width: 6, height: 6),
                        ),
                      ),
                  ],
                ),
              ),
              PopupMenuButton<_FooterTabAction>(
                tooltip: 'Acciones',
                padding: EdgeInsets.zero,
                position: PopupMenuPosition.under,
                icon: const Icon(
                  Icons.more_vert,
                  size: 16,
                  color: Color(0xFF475569),
                ),
                onSelected: (action) {
                  switch (action) {
                    case _FooterTabAction.rename:
                      onRename();
                      break;
                    case _FooterTabAction.delete:
                      onDelete?.call();
                      break;
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem<_FooterTabAction>(
                    value: _FooterTabAction.rename,
                    child: Text('Renombrar venta'),
                  ),
                  if (showDelete && onDelete != null)
                    const PopupMenuItem<_FooterTabAction>(
                      value: _FooterTabAction.delete,
                      child: Text('Eliminar venta'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FooterAddButton extends StatelessWidget {
  const _FooterAddButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: 40,
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(
              right: BorderSide(color: Color(0xFFD7E0EA)),
            ),
          ),
          child: const Center(
            child: Icon(Icons.add, size: 18, color: Color(0xFF64748B)),
          ),
        ),
      ),
    );
  }
}

enum _FooterTabAction { rename, delete }
