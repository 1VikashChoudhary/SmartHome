class ScheduledAlarm {
  final int id;
  final bool enabled;
  final int mode; // 0: Clock, 1: Delay
  final int type; // 0: Once, 1: Daily, 2: Weekly, 3: Weekday, 4: Weekend
  final int hour;
  final int minute;
  final int dayOfWeek;
  final int delayMinutes;
  final int action; // 0: Relay ON, 1: Relay OFF, 2: Relay Toggle, 3: Buzzer, 4: All ON, 5: All OFF
  final int targetRelay; // 0-4 or 255 for all
  final bool fired;
  final int? remainingSeconds;
  final DateTime fetchedAt;

  ScheduledAlarm({
    required this.id,
    this.enabled = true,
    this.mode = 0,
    this.type = 1,
    this.hour = 0,
    this.minute = 0,
    this.dayOfWeek = 0,
    this.delayMinutes = 0,
    this.action = 0,
    this.targetRelay = 0,
    this.fired = false,
    this.remainingSeconds,
    DateTime? fetchedAt,
  }) : fetchedAt = fetchedAt ?? DateTime.now();

  factory ScheduledAlarm.fromJson(Map<String, dynamic> json) {
    return ScheduledAlarm(
      id: (json['id'] as num?)?.toInt() ?? 0,
      enabled: json['en'] as bool? ?? (json['enabled'] as bool? ?? true),
      mode: (json['mode'] as num?)?.toInt() ?? 0,
      type: (json['type'] as num?)?.toInt() ?? 1,
      hour: (json['hour'] as num?)?.toInt() ?? 0,
      minute: (json['min'] as num?)?.toInt() ?? (json['minute'] as num?)?.toInt() ?? 0,
      dayOfWeek: (json['dow'] as num?)?.toInt() ?? (json['dayOfWeek'] as num?)?.toInt() ?? 0,
      delayMinutes: (json['delay'] as num?)?.toInt() ?? 0,
      action: (json['action'] as num?)?.toInt() ?? 0,
      targetRelay: (json['relay'] as num?)?.toInt() ?? (json['targetRelay'] as num?)?.toInt() ?? 0,
      fired: json['fired'] as bool? ?? false,
      remainingSeconds:
          (json['rem_sec'] as num?)?.toInt() ?? (json['remainingSeconds'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'en': enabled,
      'mode': mode,
      'type': type,
      'hour': hour,
      'min': minute,
      'dow': dayOfWeek,
      'delay': delayMinutes,
      'action': action,
      'relay': targetRelay,
      'fired': fired,
    };
  }

  String get typeLabel {
    switch (type) {
      case 0:
        return 'Once';
      case 1:
        return 'Daily';
      case 2:
        return 'Weekly (${_dowName(dayOfWeek)})';
      case 3:
        return 'Weekdays (Mon-Fri)';
      case 4:
        return 'Weekends (Sat-Sun)';
      default:
        return 'Custom';
    }
  }

  static String _dowName(int dow) {
    switch (dow) {
      case 0:
        return 'Sun';
      case 1:
        return 'Mon';
      case 2:
        return 'Tue';
      case 3:
        return 'Wed';
      case 4:
        return 'Thu';
      case 5:
        return 'Fri';
      case 6:
        return 'Sat';
      default:
        return '';
    }
  }

  String get actionLabel {
    switch (action) {
      case 0:
        return 'Turn ON';
      case 1:
        return 'Turn OFF';
      case 2:
        return 'Toggle';
      case 3:
        return 'Sound Buzzer';
      case 4:
        return 'All ON';
      case 5:
        return 'All OFF';
      default:
        return 'Action';
    }
  }

  String get timeString {
    final h = hour.toString().padLeft(2, '0');
    final m = minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  Duration? _timeUntilNextClockRun(DateTime now) {
    for (int offsetDays = 0; offsetDays <= 7; offsetDays++) {
      final candidate = DateTime(
        now.year,
        now.month,
        now.day,
        hour,
        minute,
      ).add(Duration(days: offsetDays));

      if (!candidate.isAfter(now)) continue;

      // Dart weekday: 1=Mon .. 7=Sun; ESP32 dayOfWeek: 0=Sun, 1=Mon .. 6=Sat
      final espDow = candidate.weekday % 7;
      bool matchesDay = false;
      switch (type) {
        case 0: // Once
        case 1: // Daily
          matchesDay = true;
          break;
        case 2: // Weekly
          matchesDay = (espDow == dayOfWeek);
          break;
        case 3: // Weekdays (Mon-Fri => 1..5)
          matchesDay = (espDow >= 1 && espDow <= 5);
          break;
        case 4: // Weekends (Sun=0, Sat=6)
          matchesDay = (espDow == 0 || espDow == 6);
          break;
        default:
          matchesDay = true;
      }

      if (matchesDay) {
        return candidate.difference(now);
      }
    }
    return null;
  }

  /// Calculates a live human-readable countdown until the next scheduled run.
  String get nextRunBadge {
    if (!enabled) return 'Paused';
    if (mode == 1) {
      if (fired) return 'Completed';
      final h = delayMinutes ~/ 60;
      final m = delayMinutes % 60;
      if (h > 0 && m > 0) return 'Runs within ${h}h ${m}m';
      if (h > 0) return 'Runs within ${h}h';
      return 'Runs within ${m}m';
    }
    if (type == 0 && fired) return 'Completed';

    final diff = _timeUntilNextClockRun(DateTime.now());
    if (diff != null) {
      final totalMinutes = diff.inMinutes + (diff.inSeconds % 60 > 0 ? 1 : 0);
      final d = totalMinutes ~/ (24 * 60);
      final h = (totalMinutes % (24 * 60)) ~/ 60;
      final m = totalMinutes % 60;
      if (d > 0) return 'Next run in ${d}d ${h}h';
      if (h > 0) return 'Next run in ${h}h ${m}m';
      if (m > 0) return 'Next run in ${m}m';
      return 'Running in <1m';
    }
    return 'Scheduled';
  }

  /// Formats a duration in seconds as `Xh Ym Zs`, `Ym Zs`, or `Zs`.
  static String formatDurationSeconds(int sec) {
    if (sec <= 0) return '0s';
    final h = sec ~/ 3600;
    final m = (sec % 3600) ~/ 60;
    final s = sec % 60;
    if (h > 0) return '${h}h ${m}m ${s}s';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  /// Remaining seconds at [now] interpolated locally from firmware `rem_sec`
  /// (or local clock for `SCHEDULE_CLOCK` on legacy firmware without `rem_sec`).
  int liveRemainingAt([DateTime? now]) {
    if (!enabled) return 0;
    if ((mode == 1 || type == 0) && fired) return 0;

    final current = now ?? DateTime.now();
    if (remainingSeconds != null) {
      if (remainingSeconds! <= 0) return 0;
      final rawElapsed = current.difference(fetchedAt).inSeconds;
      final elapsed = rawElapsed > 0 ? rawElapsed : 0;
      final rem = remainingSeconds! - elapsed;
      return rem > 0 ? rem : 0;
    }

    if (mode == 0) {
      final diff = _timeUntilNextClockRun(current);
      if (diff == null) return 0;
      final secs = diff.inSeconds;
      return secs > 0 ? secs : 0;
    }

    return 0;
  }

  /// Current live remaining seconds interpolated from `fetchedAt`.
  int get liveRemainingSeconds => liveRemainingAt();

  /// Whether this alarm currently has an active second-by-second countdown.
  bool get hasLiveCountdown => liveRemainingSeconds > 0;

  /// Human-readable live second-by-second countdown at [now].
  String formattedCountdownAt([DateTime? now]) =>
      formatDurationSeconds(liveRemainingAt(now));

  /// Human-readable live second-by-second countdown (`9m 55s`, `1h 2m 5s`).
  String get formattedCountdown => formattedCountdownAt();

  /// Remaining fraction in `[0.0, 1.0]` at [now] for active Delay Timers, or null.
  double? countdownProgressAt([DateTime? now]) {
    if (mode != 1 || !enabled || fired || delayMinutes <= 0) return null;
    final rem = liveRemainingAt(now);
    if (rem <= 0) return null;
    return (rem / (delayMinutes * 60)).clamp(0.0, 1.0);
  }

  /// Remaining fraction in `[0.0, 1.0]` for active Delay Timers, or null.
  double? get countdownProgress => countdownProgressAt();

  ScheduledAlarm copyWith({
    int? id,
    bool? enabled,
    int? mode,
    int? type,
    int? hour,
    int? minute,
    int? dayOfWeek,
    int? delayMinutes,
    int? action,
    int? targetRelay,
    bool? fired,
    int? remainingSeconds,
    DateTime? fetchedAt,
  }) {
    return ScheduledAlarm(
      id: id ?? this.id,
      enabled: enabled ?? this.enabled,
      mode: mode ?? this.mode,
      type: type ?? this.type,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      dayOfWeek: dayOfWeek ?? this.dayOfWeek,
      delayMinutes: delayMinutes ?? this.delayMinutes,
      action: action ?? this.action,
      targetRelay: targetRelay ?? this.targetRelay,
      fired: fired ?? this.fired,
      remainingSeconds: remainingSeconds ?? this.remainingSeconds,
      fetchedAt: fetchedAt ?? this.fetchedAt,
    );
  }
}
