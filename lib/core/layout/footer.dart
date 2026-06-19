import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import 'footer_ticket_controller.dart';

class Footer extends ConsumerWidget {
  const Footer({super.key, this.scale = 1.0});

  final double scale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(footerTicketControllerProvider);
    final tabs = controller.tabs;

    final screenSize = MediaQuery.sizeOf(context);
    final useCompactFooter =
        screenSize.width <= 1366 || screenSize.height <= 900;

    final compactScale = useCompactFooter ? 0.76 : 1.0;
    final effectiveScale = scale * compactScale;

    final footerHeight = useCompactFooter
        ? 36.0
        : (58 * effectiveScale).clamp(44.0, 64.0).toDouble();

    return SizedBox(
      height: footerHeight,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: Color(0xFFF3F6FA),
          border: Border(
            top: BorderSide(color: Color.fromARGB(255, 0, 0, 0), width: 0.3),
            bottom: BorderSide(color: Color(0xFFB2BFCC), width: 0.8),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              flex: 9,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const ClampingScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  useCompactFooter ? 6 : 8 * effectiveScale,
                  useCompactFooter ? 3 : 6 * effectiveScale,
                  useCompactFooter ? 8 : 10 * effectiveScale,
                  useCompactFooter ? 3 : 6 * effectiveScale,
                ),
                itemCount: tabs.length + 1,
                separatorBuilder: (_, _) {
                  return SizedBox(width: 6 * effectiveScale);
                },
                itemBuilder: (context, index) {
                  if (index == tabs.length) {
                    return _FooterAddButton(
                      scale: effectiveScale,
                      compact: useCompactFooter,
                      onTap: controller.add,
                    );
                  }

                  final tab = tabs[index];

                  return _FooterSaleTab(
                    index: index,
                    tab: tab,
                    scale: effectiveScale,
                    compact: useCompactFooter,
                    onTap: () => controller.select(index),
                    onRename: () => controller.rename(index),
                    onDelete: tab.canDelete
                        ? () => controller.delete(index)
                        : null,
                  );
                },
              ),
            ),
            SizedBox(
              width: (screenSize.width * 0.10).clamp(76.0, 132.0).toDouble(),
              child: _FooterVersionLabel(
                version: AppConfig.appDisplayVersion,
                compact: useCompactFooter,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FooterVersionLabel extends StatelessWidget {
  const _FooterVersionLabel({required this.version, required this.compact});

  final String version;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: double.infinity,
      padding: EdgeInsets.only(left: compact ? 6 : 8, right: compact ? 10 : 14),
      alignment: Alignment.centerRight,
      decoration: const BoxDecoration(
        border: Border(left: BorderSide(color: Color(0xFFD4DEE9), width: 0.8)),
      ),
      child: Text(
        version,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.right,
        style: TextStyle(
          color: const Color(0xFF64748B),
          fontSize: compact ? 11.2 : 12.5,
          fontWeight: FontWeight.w800,
          height: 1,
          letterSpacing: 0.05,
        ),
      ),
    );
  }
}

class _FooterSaleTab extends StatelessWidget {
  const _FooterSaleTab({
    required this.index,
    required this.tab,
    required this.scale,
    required this.compact,
    required this.onTap,
    required this.onRename,
    this.onDelete,
  });

  final int index;
  final FooterTicketTabData tab;
  final double scale;
  final bool compact;
  final VoidCallback onTap;
  final Future<void>? Function() onRename;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final isActive = tab.isActive;

    const activeColor = Color(0xFF1A56DB);
    const activeTextColor = Color(0xFF0F172A);
    const inactiveTextColor = Color(0xFF475569);
    const borderColor = Color(0xFFACB8C6);
    const inactiveBackground = Color(0xFFF8FAFC);
    const dotColor = Color(0xFFEF4444);

    final tabHeight = compact
        ? 30.0
        : (46 * scale).clamp(44.0, 50.0).toDouble();

    const tabRadius = BorderRadius.only(
      topLeft: Radius.circular(14),
      topRight: Radius.circular(6),
      bottomLeft: Radius.circular(6),
      bottomRight: Radius.circular(14),
    );

    const iconRadius = BorderRadius.only(
      topLeft: Radius.circular(10),
      topRight: Radius.circular(4),
      bottomLeft: Radius.circular(4),
      bottomRight: Radius.circular(10),
    );

    const menuRadius = BorderRadius.only(
      topLeft: Radius.circular(8),
      topRight: Radius.circular(4),
      bottomLeft: Radius.circular(4),
      bottomRight: Radius.circular(8),
    );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      height: tabHeight,
      transform: Matrix4.translationValues(
        0,
        isActive ? (compact ? -0.5 : -1.5) : 0,
        0,
      ),
      decoration: BoxDecoration(
        color: isActive ? Colors.white : inactiveBackground,
        borderRadius: tabRadius,
        border: Border.all(
          color: isActive ? activeColor.withOpacity(0.78) : borderColor,
          width: isActive ? 1.15 : 0.95,
        ),
        boxShadow: [
          BoxShadow(
            color: isActive
                ? activeColor.withOpacity(0.11)
                : Colors.black.withOpacity(0.022),
            blurRadius: isActive ? 10 : 5,
            spreadRadius: isActive ? -3 : -2,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: tabRadius,
        child: InkWell(
          onTap: onTap,
          borderRadius: tabRadius,
          hoverColor: activeColor.withOpacity(0.035),
          splashColor: activeColor.withOpacity(0.08),
          highlightColor: activeColor.withOpacity(0.025),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 5 : 7 * scale,
              compact ? 3 : 5 * scale,
              compact ? 3 : 4 * scale,
              compact ? 3 : 5 * scale,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: compact
                          ? 24.0
                          : (31 * scale).clamp(29.0, 34.0).toDouble(),
                      height: compact
                          ? 24.0
                          : (31 * scale).clamp(29.0, 34.0).toDouble(),
                      decoration: BoxDecoration(
                        color: isActive
                            ? activeColor.withOpacity(0.12)
                            : const Color(0xFFEDF2F7),
                        borderRadius: iconRadius,
                        border: Border.all(
                          color: isActive
                              ? activeColor.withOpacity(0.20)
                              : borderColor.withOpacity(0.95),
                          width: 1,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.shopping_cart_checkout_rounded,
                        size: compact
                            ? 16.0
                            : (18 * scale).clamp(17.0, 20.0).toDouble(),
                        color: isActive ? activeColor : inactiveTextColor,
                      ),
                    ),

                    if (tab.showAlertDot)
                      Positioned(
                        right: -2 * scale,
                        top: -2 * scale,
                        child: Container(
                          width: (8 * scale).clamp(7.0, 9.0).toDouble(),
                          height: (8 * scale).clamp(7.0, 9.0).toDouble(),
                          decoration: BoxDecoration(
                            color: dotColor,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 1.2),
                          ),
                        ),
                      ),
                  ],
                ),

                SizedBox(width: compact ? 6 : 8 * scale),

                Text(
                  tab.label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.visible,
                  style: TextStyle(
                    color: isActive ? activeTextColor : inactiveTextColor,
                    fontSize: compact
                        ? 13.0
                        : (14.3 * scale).clamp(13.5, 15.2).toDouble(),
                    fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
                    height: 1,
                    letterSpacing: -0.30,
                    fontFamilyFallback: const [
                      'Poppins',
                      'Segoe UI',
                      'Roboto',
                      'Arial',
                    ],
                  ),
                ),

                SizedBox(width: compact ? 5 : 7 * scale),

                PopupMenuButton<String>(
                  padding: EdgeInsets.zero,
                  tooltip: 'Opciones de la venta',
                  position: PopupMenuPosition.under,
                  offset: const Offset(0, 6),
                  elevation: 10,
                  color: Colors.white,
                  surfaceTintColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                    side: BorderSide(color: activeColor.withOpacity(0.10)),
                  ),
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
                      height: 42,
                      child: Row(
                        children: [
                          Icon(
                            Icons.drive_file_rename_outline_rounded,
                            size: 18,
                          ),
                          SizedBox(width: 10),
                          Text('Renombrar venta'),
                        ],
                      ),
                    ),
                    if (onDelete != null)
                      const PopupMenuItem<String>(
                        value: 'delete',
                        height: 42,
                        child: Row(
                          children: [
                            Icon(
                              Icons.delete_outline_rounded,
                              size: 18,
                              color: Color(0xFFDC2626),
                            ),
                            SizedBox(width: 10),
                            Text(
                              'Eliminar venta',
                              style: TextStyle(color: Color(0xFFDC2626)),
                            ),
                          ],
                        ),
                      ),
                  ],
                  child: Container(
                    width: (27 * scale)
                        .clamp(compact ? 22.0 : 25.0, 29.0)
                        .toDouble(),
                    height: (31 * scale)
                        .clamp(compact ? 24.0 : 29.0, 33.0)
                        .toDouble(),
                    decoration: BoxDecoration(
                      color: isActive
                          ? activeColor.withOpacity(0.06)
                          : Colors.transparent,
                      borderRadius: menuRadius,
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.more_vert_rounded,
                      size: compact
                          ? 16.0
                          : (18 * scale).clamp(17.0, 19.0).toDouble(),
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FooterAddButton extends StatelessWidget {
  const _FooterAddButton({
    required this.scale,
    required this.compact,
    required this.onTap,
  });

  final double scale;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final width = compact ? 44.0 : (46 * scale).clamp(44.0, 50.0).toDouble();
    final height = compact ? 30.0 : (46 * scale).clamp(44.0, 50.0).toDouble();

    const buttonRadius = BorderRadius.only(
      topLeft: Radius.circular(14),
      topRight: Radius.circular(6),
      bottomLeft: Radius.circular(6),
      bottomRight: Radius.circular(14),
    );

    return Tooltip(
      message: 'Nueva venta',
      waitDuration: const Duration(milliseconds: 350),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: buttonRadius,
          hoverColor: const Color(0xFF1A56DB).withOpacity(0.05),
          splashColor: const Color(0xFF1A56DB).withOpacity(0.10),
          child: Ink(
            width: width,
            height: height,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF1FF),
              borderRadius: buttonRadius,
              border: Border.all(
                color: const Color(0xFF1A56DB).withOpacity(0.48),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF1A56DB).withOpacity(0.08),
                  blurRadius: 8,
                  spreadRadius: -3,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(
              Icons.add_rounded,
              size: compact ? 17.0 : (23 * scale).clamp(21.0, 25.0).toDouble(),
              color: const Color(0xFF1A56DB),
            ),
          ),
        ),
      ),
    );
  }
}
