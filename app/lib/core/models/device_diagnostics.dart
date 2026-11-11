class DeviceDiagnostics {
  final int freeHeap;
  final int minHeap;
  final int totalHeap;
  final int heapFrag;
  final String uptime;
  final String resetReason;
  final String chipModel;
  final int chipRev;
  final int cpuFreq;
  final int flashSize;
  final String sdkVersion;
  final String fwVersion;
  final String fwBuild;
  final int fsUsed;
  final int fsTotal;
  final String otaStatus;
  final String otaPartition;
  final String otaState;
  final bool otaRollbackPossible;

  DeviceDiagnostics({
    required this.freeHeap,
    required this.minHeap,
    required this.totalHeap,
    required this.heapFrag,
    required this.uptime,
    required this.resetReason,
    required this.chipModel,
    required this.chipRev,
    required this.cpuFreq,
    required this.flashSize,
    required this.sdkVersion,
    required this.fwVersion,
    required this.fwBuild,
    required this.fsUsed,
    required this.fsTotal,
    required this.otaStatus,
    this.otaPartition = 'app0',
    this.otaState = 'Stable',
    this.otaRollbackPossible = false,
  });

  factory DeviceDiagnostics.fromJson(Map<String, dynamic> json) {
    return DeviceDiagnostics(
      freeHeap: (json['free_heap'] as num?)?.toInt() ?? 0,
      minHeap: (json['min_heap'] as num?)?.toInt() ?? 0,
      totalHeap: (json['total_heap'] as num?)?.toInt() ?? 0,
      heapFrag: (json['heap_frag'] as num?)?.toInt() ?? 0,
      uptime: json['uptime'] as String? ?? 'N/A',
      resetReason: json['reset_reason'] as String? ?? 'Unknown',
      chipModel: json['chip_model'] as String? ?? 'ESP32',
      chipRev: (json['chip_rev'] as num?)?.toInt() ?? 1,
      cpuFreq: (json['cpu_freq'] as num?)?.toInt() ?? 240,
      flashSize: (json['flash_size'] as num?)?.toInt() ?? 4194304,
      sdkVersion: json['sdk_version'] as String? ?? 'ESP-IDF',
      fwVersion: json['fw_version'] as String? ?? '3.2.0',
      fwBuild: json['fw_build'] as String? ?? '',
      fsUsed: (json['fs_used'] as num?)?.toInt() ?? 0,
      fsTotal: (json['fs_total'] as num?)?.toInt() ?? 1,
      otaStatus: json['ota_status'] as String? ?? 'Idle',
      otaPartition: json['ota_partition'] as String? ?? 'app0',
      otaState: json['ota_state'] as String? ?? 'Stable',
      otaRollbackPossible: json['ota_rollback_possible'] as bool? ?? false,
    );
  }
}
