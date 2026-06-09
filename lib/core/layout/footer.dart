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
    const dotColor = Color(0xFFEF4444);

    return Material(
      color: isActive ? Colors.white : inactiveBackground,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: BoxConstraints(
            minWidth: 150 * scale,
            maxWidth: 176 * scale,
          ),
          padding: EdgeInsets.symmetric(horizontal: 10 * scale),
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
                Icons.shopping_cart_checkout_rounded,
                size: 17.5 * scale,
                color: isActive ? activeColor : textColor,
              ),
              SizedBox(width: 6 * scale),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 5 * scale),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tab.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.2 * scale,
                          fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                          height: 1.25,
                          color: isActive ? activeTextColor : textColor,
                          letterSpacing: -0.1,
                        ),
                      ),
                      SizedBox(height: 3 * scale),
                      SizedBox(
                        height: 6 * scale,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: tab.showAlertDot
                              ? Container(
                                  width: 6 * scale,
                                  height: 6 * scale,
                                  decoration: const BoxDecoration(
                                    color: dotColor,
                                    shape: BoxShape.circle,
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(width: 1 * scale),
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
                    horizontal: 2 * scale,
                    vertical: 7 * scale,
                  ),
                  child: Icon(
                    Icons.more_vert,
                    size: 18 * scale,
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
    final size = 34.0 * scale;
    final radius = 8.0 * scale;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(radius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: Container(
          width: size,
          height: size,
          margin: EdgeInsets.symmetric(vertical: 4 * scale),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: const Color(0xFFD0D5DD)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Icon(
            Icons.add,
            size: 20 * scale,
            color: const Color(0xFF334155),
          ),
        ),
      ),
    );
  }
}
