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
        color: Color(0xFFF8FAFC),
        border: Border(top: BorderSide(color: Color(0xFFE2E8F0), width: 1.0)),
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
              child: _FooterAddButton(scale: scale, onTap: controller.add),
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
    const inactiveBackground = Color(0xFFF9FBFD);
    const borderColor = Color(0xFFE2E8F0);
    const textColor = Color(0xFF0B1220);
    const activeTextColor = Color(0xFF0B1220);
    const dotColor = Color(0xFFEF4444);

    return Material(
      color: isActive ? Colors.white : inactiveBackground,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: BoxConstraints(
            minWidth: index == 0 ? 108 * scale : 128 * scale,
            maxWidth: index == 0 ? 228 * scale : 162 * scale,
            minHeight: 42 * scale,
          ),
          padding: EdgeInsets.symmetric(horizontal: 8 * scale),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: isActive ? activeColor : borderColor,
                width: isActive ? 2.0 : 1.0,
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
              SizedBox(
                width: 24 * scale,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    Icon(
                      Icons.shopping_cart_checkout_rounded,
                      size: 19.5 * scale,
                      color: isActive ? activeColor : textColor,
                    ),
                    if (tab.showAlertDot)
                      Positioned(
                        right: -1 * scale,
                        top: 1 * scale,
                        child: Container(
                          width: 7 * scale,
                          height: 7 * scale,
                          decoration: BoxDecoration(
                            color: dotColor,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isActive
                                  ? Colors.white
                                  : inactiveBackground,
                              width: 1,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(width: 6 * scale),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 3 * scale),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          tab.label,
                          maxLines: 1,
                          overflow: TextOverflow.visible,
                          style: TextStyle(
                            fontSize: 14.2 * scale,
                            fontWeight: FontWeight.w500,
                            height: 1.18,
                            color: isActive ? activeTextColor : textColor,
                            letterSpacing: -0.22,
                          ),
                        ),
                      ),
                      SizedBox(height: 1 * scale),
                    ],
                  ),
                ),
              ),
              SizedBox(width: 3 * scale),
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
                    vertical: 8 * scale,
                  ),
                  child: Icon(
                    Icons.more_vert,
                    size: 19 * scale,
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
  const _FooterAddButton({required this.scale, required this.onTap});

  final double scale;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final size = 38.0 * scale;
    final radius = 8.0 * scale;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(radius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: Container(
          width: size,
          height: size,
          margin: EdgeInsets.symmetric(vertical: 2 * scale),
          decoration: BoxDecoration(
            color: const Color(0x00000000),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          alignment: Alignment.center,
          child: Icon(
            Icons.add_rounded,
            size: 22 * scale,
            color: const Color(0xFF1A56DB),
          ),
        ),
      ),
    );
  }
}
