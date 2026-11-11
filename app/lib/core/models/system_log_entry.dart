class SystemLogEntry {
  final int timestamp;
  final int level; // 0: INFO, 1: WARN, 2: ERROR
  final String source;
  final String message;

  SystemLogEntry({
    required this.timestamp,
    required this.level,
    required this.source,
    required this.message,
  });

  factory SystemLogEntry.fromJson(Map<String, dynamic> json) {
    return SystemLogEntry(
      timestamp: (json['ts'] as num?)?.toInt() ?? 0,
      level: (json['lvl'] as num?)?.toInt() ?? 0,
      source: json['src'] as String? ?? 'System',
      message: json['msg'] as String? ?? '',
    );
  }

  String get levelLabel {
    switch (level) {
      case 0:
        return 'INFO';
      case 1:
        return 'WARN';
      case 2:
        return 'ERROR';
      default:
        return 'LOG';
    }
  }

  String get formattedTime {
    if (timestamp > 1600000000) {
      final dt = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      final s = dt.second.toString().padLeft(2, '0');
      return '$h:$m:$s';
    }
    // Uptime seconds
    final h = (timestamp ~/ 3600).toString().padLeft(2, '0');
    final m = ((timestamp % 3600) ~/ 60).toString().padLeft(2, '0');
    final s = (timestamp % 60).toString().padLeft(2, '0');
    return '+$h:$m:$s';
  }
}
