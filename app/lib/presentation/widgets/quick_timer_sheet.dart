import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

class QuickTimerSheet extends StatefulWidget {
  final String relayName;
  final bool currentState;
  final void Function(String action, int durationSeconds) onStartTimer;

  const QuickTimerSheet({
    super.key,
    required this.relayName,
    required this.currentState,
    required this.onStartTimer,
  });

  @override
  State<QuickTimerSheet> createState() => _QuickTimerSheetState();
}

class _QuickTimerSheetState extends State<QuickTimerSheet> {
  int _selectedHours = 0;
  int _selectedMinutes = 10;
  late String _action;

  @override
  void initState() {
    super.initState();
    // Default action:
    // If relay is ON  -> auto-turn OFF ('off') after countdown finishes
    // If relay is OFF -> delay-turn ON ('on') after countdown finishes
    _action = widget.currentState ? 'off' : 'on';
  }

  void _setPreset(int minutes) {
    setState(() {
      _selectedHours = minutes ~/ 60;
      _selectedMinutes = minutes % 60;
    });
  }

  String _formatDuration(int sec) {
    if (sec <= 0) return '0m';
    final h = sec ~/ 3600;
    final m = (sec % 3600) ~/ 60;
    if (h > 0 && m > 0) return '${h}h ${m}m';
    if (h > 0) return '${h}h';
    return '${m}m';
  }

  @override
  Widget build(BuildContext context) {
    final totalSec = (_selectedHours * 3600) + (_selectedMinutes * 60);

    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom + 20,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.cardBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(Icons.timer_outlined, color: AppColors.primary, size: 24),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Quick Timer: ${widget.relayName}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Quick Presets',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildPresetChip(5, '5m'),
                _buildPresetChip(10, '10m'),
                _buildPresetChip(30, '30m'),
                _buildPresetChip(60, '1h'),
                _buildPresetChip(120, '2h'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Hours', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<int>(
                      key: ValueKey('hours_$_selectedHours'),
                      initialValue: _selectedHours,
                      dropdownColor: AppColors.surfaceElevated,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: AppColors.card,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      ),
                      items: List.generate(24, (i) => DropdownMenuItem(value: i, child: Text('$i h'))),
                      onChanged: (v) => setState(() => _selectedHours = v ?? 0),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Minutes', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<int>(
                      key: ValueKey('minutes_$_selectedMinutes'),
                      initialValue: _selectedMinutes,
                      dropdownColor: AppColors.surfaceElevated,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: AppColors.card,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      ),
                      items: List.generate(60, (i) => DropdownMenuItem(value: i, child: Text('$i m'))),
                      onChanged: (v) => setState(() => _selectedMinutes = v ?? 0),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Action when timer finishes', style: TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: ChoiceChip(
                  label: const Center(child: Text('Auto Turn OFF', style: TextStyle(fontWeight: FontWeight.w600))),
                  selected: _action == 'off',
                  selectedColor: AppColors.danger.withValues(alpha: 0.25),
                  side: BorderSide(color: _action == 'off' ? AppColors.danger : AppColors.cardBorder),
                  onSelected: (s) => setState(() => _action = 'off'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ChoiceChip(
                  label: const Center(child: Text('Delay Turn ON', style: TextStyle(fontWeight: FontWeight.w600))),
                  selected: _action == 'on',
                  selectedColor: AppColors.success.withValues(alpha: 0.25),
                  side: BorderSide(color: _action == 'on' ? AppColors.success : AppColors.cardBorder),
                  onSelected: (s) => setState(() => _action = 'on'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.cardBorder, width: 0.7),
            ),
            child: Row(
              children: [
                Icon(
                  _action == 'off'
                      ? Icons.power_settings_new_rounded
                      : Icons.schedule_rounded,
                  size: 16,
                  color: _action == 'off'
                      ? AppColors.danger
                      : AppColors.success,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _action == 'off'
                        ? 'Counts down for ${_formatDuration(totalSec)}, then turns OFF ${widget.relayName}.'
                        : 'Counts down for ${_formatDuration(totalSec)}, then turns ON ${widget.relayName}.',
                    style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary, height: 1.3),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.3),
                disabledForegroundColor: Colors.white.withValues(alpha: 0.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: totalSec > 0
                  ? () {
                      widget.onStartTimer(_action, totalSec);
                      Navigator.pop(context);
                    }
                  : null,
              child: Text(
                totalSec <= 0
                    ? 'Select Duration'
                    : _action == 'off'
                        ? 'Start Turn-OFF Timer (${_formatDuration(totalSec)})'
                        : 'Start Turn-ON Timer (${_formatDuration(totalSec)})',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPresetChip(int minutes, String label) {
    final isSelected = (_selectedHours * 60 + _selectedMinutes) == minutes;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        selectedColor: AppColors.primary.withValues(alpha: 0.25),
        side: BorderSide(color: isSelected ? AppColors.primary : AppColors.cardBorder),
        onSelected: (_) => _setPreset(minutes),
      ),
    );
  }
}
