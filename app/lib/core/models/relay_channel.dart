class RelayChannel {
  final int index;
  int get id => index;
  final bool enabled;
  final bool switchEnabled;
  final String name;
  final bool state;
  final bool timerActive;
  final bool timerTarget;
  final int timerRemaining; // seconds
  final int trigger;
  final int boot;
  final int autoOff;
  final int autoOn;
  final int cycles;
  final bool failsafe;
  final String iconType;
  final String? activeRule;

  RelayChannel({
    required this.index,
    this.enabled = true,
    this.switchEnabled = true,
    required this.name,
    required this.state,
    this.timerActive = false,
    this.timerTarget = false,
    this.timerRemaining = 0,
    this.trigger = 0,
    this.boot = 0,
    this.autoOff = 0,
    this.autoOn = 0,
    this.cycles = 0,
    this.failsafe = false,
    this.iconType = 'light',
    this.activeRule,
  });

  static int _parseInt(dynamic val, [int def = 0]) {
    if (val == null) return def;
    if (val is num) return val.toInt();
    if (val is String) return int.tryParse(val.trim()) ?? def;
    if (val is bool) return val ? 1 : 0;
    return def;
  }

  static bool _parseBool(dynamic val, [bool def = false]) {
    if (val == null) return def;
    if (val is bool) return val;
    if (val is num) return val != 0;
    if (val is String) {
      final s = val.trim().toLowerCase();
      return s == 'true' || s == '1' || s == 'yes' || s == 'on';
    }
    return def;
  }

  factory RelayChannel.fromJson(int index, Map<String, dynamic> json) {
    return RelayChannel(
      index: _parseInt(json['id'] ?? json['index'], index),
      enabled: _parseBool(json['enabled'], true),
      switchEnabled: _parseBool(json['switch_enabled'] ?? json['switchEnabled'], true),
      name: json['name']?.toString().isNotEmpty == true
          ? json['name'].toString()
          : 'Relay ${index + 1}',
      state: _parseBool(json['state'], false),
      timerActive: _parseBool(json['timer_active'] ?? json['timerActive'], false),
      timerTarget: _parseBool(json['timer_target'] ?? json['timerTarget'], false),
      timerRemaining: _parseInt(json['timer_remaining'] ?? json['timerRemaining'], 0),
      trigger: _parseInt(json['trigger'], 0),
      boot: _parseInt(json['boot'], 0),
      autoOff: _parseInt(json['autoOff'] ?? json['auto_off'], 0),
      autoOn: _parseInt(json['autoOn'] ?? json['auto_on'], 0),
      cycles: _parseInt(json['cycles'], 0),
      failsafe: _parseBool(json['failsafe'], false),
      iconType: (json['icon']?.toString().trim().isNotEmpty == true)
          ? json['icon'].toString().trim().toLowerCase()
          : 'light',
      activeRule: (json['active_rule']?.toString().trim().isNotEmpty == true)
          ? json['active_rule'].toString().trim()
          : null,
    );
  }

  RelayChannel copyWith({
    bool? enabled,
    bool? switchEnabled,
    String? name,
    bool? state,
    bool? timerActive,
    bool? timerTarget,
    int? timerRemaining,
    int? trigger,
    int? boot,
    int? autoOff,
    int? autoOn,
    int? cycles,
    bool? failsafe,
    String? iconType,
    String? activeRule,
    bool clearActiveRule = false,
  }) {
    return RelayChannel(
      index: index,
      enabled: enabled ?? this.enabled,
      switchEnabled: switchEnabled ?? this.switchEnabled,
      name: name ?? this.name,
      state: state ?? this.state,
      timerActive: timerActive ?? this.timerActive,
      timerTarget: timerTarget ?? this.timerTarget,
      timerRemaining: timerRemaining ?? this.timerRemaining,
      trigger: trigger ?? this.trigger,
      boot: boot ?? this.boot,
      autoOff: autoOff ?? this.autoOff,
      autoOn: autoOn ?? this.autoOn,
      cycles: cycles ?? this.cycles,
      failsafe: failsafe ?? this.failsafe,
      iconType: iconType ?? this.iconType,
      activeRule: clearActiveRule ? null : (activeRule ?? this.activeRule),
    );
  }

  Map<String, dynamic> toJson() => {
    'index': index,
    'enabled': enabled,
    'switch_enabled': switchEnabled,
    'name': name,
    'state': state,
    'timer_active': timerActive,
    'timer_target': timerTarget,
    'timer_remaining': timerRemaining,
    'trigger': trigger,
    'boot': boot,
    'autoOff': autoOff,
    'autoOn': autoOn,
    'cycles': cycles,
    'failsafe': failsafe,
    'icon': iconType,
    if (activeRule != null) 'active_rule': activeRule,
  };
}
