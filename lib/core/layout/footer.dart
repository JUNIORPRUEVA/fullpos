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
      decoration: BoxDecoration(
        color: const Color(0xFFD6DEE8),
        border: Border(
          top: BorderSide(color: const Color(0xFFB6C3D3), width: 2.5),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: 8 * scale),
              itemCount: tabs.length,
              separatorBuilder: (context, index) =>
                  SizedBox(width: 1 * scale),
              itemBuilder: (context, index) {
                final tab = tabs[index];
                return _FooterSaleTab(
                  tab: tab,
                  scale: scale,
                  onTap: () => controller.select(index),
                );
              },
            ),
          ),
          Padding(
            padding: EdgeInsets.only(left: 6 * scale, right: 10 * scale),
            child: _FooterAddButton(
              scale: scale,
              onTap: controller.add,
            ),
          ),
        ],
      ),
    );
  }
}

class _FooterSaleTab extends StatelessWidget {
  const _FooterSaleTab({
    required this.tab,
    required this.scale,
    required this.onTap,
  });

  final FooterTicketTabData tab;
  final double scale;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isActive = tab.isActive;
    const activeColor = Color(0xFF17B5B0);
    const textColor = Color(0xFF334155);
    const activeTextColor = Color(0xFF1E293B);

    return Material(
      color: isActive ? Colors.white : const Color(0xFFF8FAFC),
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: BoxConstraints(minWidth: 148 * scale, maxWidth: 176 * scale),
          padding: EdgeInsets.symmetric(horizontal: 12 * scale),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: isActive ? activeColor : Colors.transparent,
                width: 2,
              ),
              right: BorderSide(color: const Color(0xFFD9E2F1)),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.shopping_bag_outlined,
                size: 14 * scale,
                color: isActive ? activeColor : textColor,
              ),
              SizedBox(width: 8 * scale),
              Expanded(
                child: Text(
                  tab.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.2 * scale,
                    fontWeight: FontWeight.w500,
                    height: 0.95,
                    color: isActive ? activeTextColor : textColor,
                    letterSpacing: -0.1,
                  ),
                ),
              ),
              if (tab.showAlertDot) ...[
                SizedBox(width: 8 * scale),
                Container(
                  width: 6 * scale,
                  height: 6 * scale,
                  decoration: const BoxDecoration(
                    color: Color(0xFFEF4444),
                    shape: BoxShape.circle,
                  ),
                ),
              ],
              SizedBox(width: 8 * scale),
              Icon(
                Icons.more_vert,
                size: 15 * scale,
                color: const Color(0xFF64748B),
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
          width: 34 * scale,
          height: 34 * scale,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6 * scale),
            border: Border.all(color: const Color(0xFFD9E2F1)),
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
