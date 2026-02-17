import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_sizes.dart';
import '../../theme/app_colors.dart';
import '../utils/date_time_formatter.dart';
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
    final businessSettings = ref.watch(businessSettingsProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final shadowColor = theme.shadowColor;
    final footerTextColor = Colors.white;
    final activeColor = AppColors.lightBlueHover;
    final borderColor = scheme.outlineVariant.withOpacity(0.35);
    final footerBg = AppColors.primaryBlue;
    final year = DateTime.now().year;
    final s = widget.scale.clamp(0.65, 1.12);
    final h = (AppSizes.footerHeight * s).clamp(26.0, 40.0);
    final font = (11 * s).clamp(10.0, 12.5);
    final infoFont = (10.5 * s).clamp(9.0, 12.0);
    final pad = (AppSizes.paddingM * s).clamp(10.0, 18.0);
    final timestamp = DateTimeFormatter.formatFullDateTime(_currentTime);

    return Container(
      height: h,
      decoration: BoxDecoration(
        color: footerBg,
        border: Border(top: BorderSide(color: borderColor, width: 1.5)),
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
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                timestamp,
                style: TextStyle(
                    color: Colors.white.withOpacity(0.88),
                  fontSize: infoFont,
                ),
              ),
              SizedBox(width: (10 * s).clamp(8.0, 12.0)),
              Text(
                'v1.0.0 Local',
                style: TextStyle(
                  color: activeColor,
                  fontSize: infoFont,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
