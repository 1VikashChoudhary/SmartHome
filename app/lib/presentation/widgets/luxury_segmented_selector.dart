import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

class LuxurySegmentedSelector<T> extends StatelessWidget {
  final List<T> values;
  final Map<T, String> labels;
  final Map<T, IconData>? icons;
  final T selectedValue;
  final ValueChanged<T> onSelected;

  const LuxurySegmentedSelector({
    super.key,
    required this.values,
    required this.labels,
    this.icons,
    required this.selectedValue,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder, width: 1),
      ),
      child: Row(
        children: values.map((val) {
          final isSelected = val == selectedValue;
          final label = labels[val] ?? '';
          final icon = icons?[val];

          return Expanded(
            child: GestureDetector(
              onTap: () => onSelected(val),
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected
                      ? (isDark ? AppColors.primary : Colors.white)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: isDark
                                ? AppColors.primary.withValues(alpha: 0.35)
                                : Colors.black.withValues(alpha: 0.08),
                            blurRadius: isDark ? 8 : 6,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (icon != null) ...[
                      Icon(
                        icon,
                        size: 15,
                        color: isSelected
                            ? (isDark ? Colors.white : AppColors.primary)
                            : AppColors.textSecondary,
                      ),
                      const SizedBox(width: 5),
                    ],
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                        color: isSelected
                            ? (isDark ? Colors.white : AppColors.primary)
                            : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
