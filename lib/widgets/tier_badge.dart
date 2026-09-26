import 'package:flutter/material.dart';
import '../core/constants/enums.dart';
import '../core/theme/app_theme.dart';

/// 회원의 급수를 표시하는 뱃지 위젯
class TierBadge extends StatelessWidget {
  final Tier tier;
  final bool showWeight;

  const TierBadge({
    super.key,
    required this.tier,
    this.showWeight = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.getTierColor(tier);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        showWeight ? '${tier.label} (${tier.weight}점)' : tier.label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
