import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_sizes.dart';
import '../theme/color_utils.dart';
import '../utils/date_time_formatter.dart';
import '../../features/settings/providers/theme_provider.dart';
import '../../features/settings/providers/business_settings_provider.dart';

/// Footer del layout principal
class Footer extends ConsumerStatefulWidget {
  const Footer({super.key, this.scale = 1.0});

  final double scale;

  @override
  ConsumerState<Footer> createState() => _FooterState();
}

class _FooterState extends ConsumerState<Footer> {
  DateTime _currentTime = DateTime.now();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) {
        setState(() => _currentTime = DateTime.now());
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeSettings = ref.watch(themeProvider);
    final businessSettings = ref.watch(businessSettingsProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final shadowColor = theme.shadowColor;
    final footerTextColor = ColorUtils.ensureReadableColor(
      themeSettings.footerTextColor,
      themeSettings.footerColor,
    );
    final activeColor = themeSettings
        .sidebarActiveColor; // Usar el color activo para la versión
    final borderColor = scheme.outlineVariant.withOpacity(0.35);
    final footerBg = themeSettings.footerColor;
    final year = DateTime.now().year;
    final s = widget.scale.clamp(0.65, 1.12);
    final h = (AppSizes.footerHeight * s).clamp(32.0, 44.0);
    final font = (12 * s).clamp(11.0, 13.0);
    final pad = AppSizes.paddingL * s;
    final timestamp = DateTimeFormatter.formatFullDateTime(_currentTime);

    return Container(
      height: h,
      decoration: BoxDecoration(
        color: footerBg,
        border: Border(top: BorderSide(color: borderColor, width: 2)),
        boxShadow: [
          BoxShadow(
            color: shadowColor.withOpacity(0.25),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
          BoxShadow(
            color: scheme.onSurface.withOpacity(0.08),
            blurRadius: 6,
            offset: const Offset(0, 1),
            spreadRadius: -2,
          ),
        ],
      ),
      padding: EdgeInsets.symmetric(horizontal: pad),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '© $year ${businessSettings.businessName.isNotEmpty ? businessSettings.businessName : 'FULLTECH, SRL'} - Sistema POS',
              style: TextStyle(color: footerTextColor, fontSize: font),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                timestamp,
                style: TextStyle(
                  color: footerTextColor.withOpacity(0.8),
                  fontSize: (10 * s).clamp(9.0, 11.0),
                ),
              ),
              Text(
                'v1.0.0 Local',
                style: TextStyle(
                  color: activeColor,
                  fontSize: font,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
