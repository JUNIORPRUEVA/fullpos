import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'footer_ticket_controller.dart';

class Footer extends ConsumerWidget {
  const Footer({super.key, this.scale = 1.0});

  final double scale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(footerTicketControllerProvider);
    final tabs = controller.tabs;

    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Color(0xFFF6F0D8),
        border: Border(
          top: BorderSide(color: Color(0xFFD3C7A5), width: 2.0),
        ),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: 0),
        itemCount: tabs.length + 1,
        separatorBuilder: (context, index) => SizedBox(width: 1 * scale),
        itemBuilder: (context, index) {
          if (index == tabs.length) {
            return Padding(
              padding: EdgeInsets.only(left: 0, right: 10 * scale),
              child: _FooterAddButton(
                scale: scale,
                onTap: controller.add,
              ),
            );
          }

          final tab = tabs[index];
          return _FooterSaleTab(
            index: index,
            tab: tab,
            scale: scale,
            onTap: () => controller.select(index),
            onRename: () => controller.rename(index),
            onDelete: tab.canDelete ? () => controller.delete(index) : null,
          );
        },
      ),
    );
  }
}

class _FooterSaleTab extends StatelessWidget {
  const _FooterSaleTab({
    required this.index,
    required this.tab,
    required this.scale,
    required this.onTap,
    required this.onRename,
    this.onDelete,
  });

  final int index;
  final FooterTicketTabData tab;
  final double scale;
  final VoidCallback onTap;
  final Future<void>? Function() onRename;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final isActive = tab.isActive;
    const activeColor = Color(0xFF1A56DB);
    const inactiveBackground = Color(0xFFF8FAFC);
    const borderColor = Color(0xFFD0D5DD);
    const textColor = Color(0xFF344256);
    const activeTextColor = Color(0xFF1F3147);

    return Material(
      color: isActive ? Colors.white : inactiveBackground,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: BoxConstraints(
            minWidth: 152 * scale,
            maxWidth: 184 * scale,
          ),
          padding: EdgeInsets.symmetric(horizontal: 12 * scale),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: isActive ? activeColor : const Color(0xFFD8D0B6),
                width: isActive ? 2.4 : 1.4,
              ),
              bottom: const BorderSide(color: borderColor),
              right: const BorderSide(color: borderColor),
              left: index == 0
                  ? const BorderSide(color: borderColor)
                  : BorderSide.none,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                Icons.shopping_bag_outlined,
                size: 15 * scale,
                color: isActive ? activeColor : textColor,
              ),
              SizedBox(width: 7 * scale),
              Expanded(
                child: Text(
                  tab.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.1 * scale,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                    height: 1.16,
                    color: isActive ? activeTextColor : textColor,
                    letterSpacing: -0.08,
                  ),
                ),
              ),
              if (tab.showAlertDot) ...[
                SizedBox(width: 7 * scale),
                Container(
                  width: 6 * scale,
                  height: 6 * scale,
                  decoration: const BoxDecoration(
                    color: Color(0xFFEF4444),
                    shape: BoxShape.circle,
                  ),
                ),
              ],
              SizedBox(width: 2 * scale),
              PopupMenuButton<String>(
                padding: EdgeInsets.zero,
                tooltip: 'Opciones de la venta',
                position: PopupMenuPosition.under,
                onSelected: (value) async {
                  if (value == 'rename') {
                    await onRename();
                    return;
                  }
                  if (value == 'delete') {
                    onDelete?.call();
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem<String>(
                    value: 'rename',
                    child: Row(
                      children: [
                        Icon(Icons.drive_file_rename_outline, size: 18),
                        SizedBox(width: 10),
                        Text('Renombrar venta'),
                      ],
                    ),
                  ),
                  if (onDelete != null)
                    const PopupMenuItem<String>(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline, size: 18),
                          SizedBox(width: 10),
                          Text('Eliminar venta'),
                        ],
                      ),
                    ),
                ],
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: 4 * scale,
                    vertical: 8 * scale,
                  ),
                  child: Icon(
                    Icons.more_vert,
                    size: 16 * scale,
                    color: const Color(0xFF64748B),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FooterAddButton extends StatelessWidget {
  const _FooterAddButton({
    required this.scale,
    required this.onTap,
  });

  final double scale;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(6 * scale),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6 * scale),
        child: Container(
          width: 36 * scale,
          height: 36 * scale,
          margin: EdgeInsets.only(top: 4 * scale),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6 * scale),
            border: Border.all(color: const Color(0xFFD0D5DD)),
          ),
          child: Icon(
            Icons.add,
            size: 18 * scale,
            color: const Color(0xFF64748B),
          ),
        ),
      ),
    );
  }
}
