import 'package:flutter/material.dart';
import '../../core/models/hardware_profile.dart';
import '../../core/models/smart_device.dart';
import '../../core/theme/app_colors.dart';
import '../../services/device_manager.dart';
import 'glass_card.dart';

class HardwareConfigSheet extends StatefulWidget {
  final SmartDevice device;
  final DeviceManager manager;

  const HardwareConfigSheet({
    super.key,
    required this.device,
    required this.manager,
  });

  static void show(BuildContext context, SmartDevice device, DeviceManager manager) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => HardwareConfigSheet(device: device, manager: manager),
    );
  }

  @override
  State<HardwareConfigSheet> createState() => _HardwareConfigSheetState();
}

class _HardwareConfigSheetState extends State<HardwareConfigSheet> {
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isCustomMode = false;
  String? _errorMessage;

  late TextEditingController _boardNameController;
  int _numRelays = 5;
  List<ChannelHardwareConfig> _channels = [];

  ClimateSensorType _dhtType = ClimateSensorType.dht22;
  int _dhtPin = 4;

  LightSensorType _lightType = LightSensorType.none;

  MotionSensorType _motionType = MotionSensorType.none;
  int _motionPin = 32;

  ProbeSensorType _probeType = ProbeSensorType.none;
  int _probePin = 15;

  UltrasonicSensorType _ultrasonicType = UltrasonicSensorType.none;
  int _trigPin = 15;
  int _echoPin = 35;
  late TextEditingController _tankDepthController;
  late TextEditingController _tankAirGapController;

  bool _mq2Enabled = true;
  int _mq2AnalogPin = 34;
  int _mq2DigitalPin = 35;

  bool _buzzerEnabled = true;
  int _buzzerPin = 5;

  bool _lcdEnabled = true;
  int _lcdI2cAddr = 39; // 0x27
  int _lcdCols = 16;
  int _lcdRows = 2;
  int _i2cSdaPin = 21;
  int _i2cSclPin = 22;

  int _btnMultiPin = 33;

  @override
  void initState() {
    super.initState();
    _numRelays = widget.device.isEsp8266 ? 2 : 5;
    if (widget.device.isEsp8266) {
      _mq2AnalogPin = 17; // A0
      _mq2DigitalPin = 255;
      _buzzerPin = 2;
      _i2cSdaPin = 4;
      _i2cSclPin = 5;
      _btnMultiPin = 0;
    }
    _boardNameController = TextEditingController(
      text: widget.device.isEsp8266 ? 'SmartHome ESP8266 2-CH Dual' : 'SmartHome 5-CH Standard',
    );
    _tankDepthController = TextEditingController(text: '150');
    _tankAirGapController = TextEditingController(text: '15');
    _loadHardwareProfile();
  }

  @override
  void dispose() {
    _boardNameController.dispose();
    _tankDepthController.dispose();
    _tankAirGapController.dispose();
    super.dispose();
  }

  Future<void> _loadHardwareProfile() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final profile = await widget.manager.apiClient.fetchHardwareProfile(
        widget.device.ip,
        password: widget.device.authPassword,
        username: widget.device.authUsername,
      );

      if (profile != null) {
        _applyProfileToState(profile);
      } else {
        final defaultCount = widget.device.isEsp8266 ? 2 : 5;
        _initDefaultChannels(defaultCount);
      }
    } catch (_) {
      final defaultCount = widget.device.isEsp8266 ? 2 : 5;
      _initDefaultChannels(defaultCount);
      _errorMessage = 'Could not fetch live profile from controller. Loaded defaults.';
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _applyProfileToState(HardwareProfile p) {
    _boardNameController.text = p.boardName;
    _numRelays = p.numRelays.clamp(0, 8);
    _channels = List.from(p.channels);

    final presets = HardwareProfile.presetsFor(widget.device.isEsp8266);
    _isCustomMode = !presets.contains(p.boardName);

    final isEsp8266 = widget.device.isEsp8266;
    final defaultRelays = isEsp8266
        ? [12, 14, 4, 5, 13, 15, 0, 16]
        : [16, 17, 18, 19, 23, 25, 26, 27];
    final defaultSwitches = isEsp8266
        ? [13, 16, 255, 255, 255, 255, 255, 255]
        : [13, 14, 27, 26, 25, 255, 255, 255];

    while (_channels.length < _numRelays) {
      final idx = _channels.length;
      _channels.add(ChannelHardwareConfig(
        relayPin: idx < defaultRelays.length ? defaultRelays[idx] : 255,
        switchPin: idx < defaultSwitches.length ? defaultSwitches[idx] : 255,
        switchMode: SwitchMode.toggle,
        triggerMode: 0,
      ));
    }

    _dhtType = p.dhtType;
    _dhtPin = p.dhtPin;
    _lightType = p.lightType;
    _motionType = p.motionType;
    _motionPin = p.motionPin;
    _probeType = p.probeType;
    _probePin = p.probePin;
    _ultrasonicType = p.ultrasonicType;
    _trigPin = p.trigPin;
    _echoPin = p.echoPin;
    _tankDepthController.text = p.tankDepthCm.toString();
    _tankAirGapController.text = p.tankAirGapCm.toString();
    _mq2Enabled = p.mq2Enabled;
    _mq2AnalogPin = p.mq2AnalogPin;
    _mq2DigitalPin = p.mq2DigitalPin;
    _buzzerEnabled = p.buzzerEnabled;
    _buzzerPin = p.buzzerPin;
    _lcdEnabled = p.lcdEnabled;
    _lcdI2cAddr = p.lcdI2cAddr;
    _lcdCols = p.lcdCols;
    _lcdRows = p.lcdRows;
    _i2cSdaPin = p.i2cSdaPin;
    _i2cSclPin = p.i2cSclPin;
    _btnMultiPin = p.btnMultiPin;
  }

  void _initDefaultChannels(int count) {
    _numRelays = count;
    _channels.clear();
    final isEsp8266 = widget.device.isEsp8266;
    final defaultRelays = isEsp8266
        ? [12, 14, 4, 5, 13, 15, 0, 16]
        : [16, 17, 18, 19, 23, 25, 26, 27];
    final defaultSwitches = isEsp8266
        ? [13, 16, 255, 255, 255, 255, 255, 255]
        : [13, 14, 27, 26, 25, 255, 255, 255];
    for (int i = 0; i < count; i++) {
      final sPin = i < defaultSwitches.length ? defaultSwitches[i] : 255;
      final rPin = i < defaultRelays.length ? defaultRelays[i] : 255;
      _channels.add(ChannelHardwareConfig(
        enabled: true,
        switchEnabled: (sPin != 255),
        relayPin: rPin,
        switchPin: sPin,
        switchMode: SwitchMode.toggle,
        triggerMode: 0,
      ));
    }
  }

  void _addChannel() {
    if (_numRelays >= 8) return;
    setState(() {
      _isCustomMode = true;
      _numRelays++;
      final isEsp8266 = widget.device.isEsp8266;
      final defaultRelays = isEsp8266
          ? [12, 14, 4, 5, 13, 15, 0, 16]
          : [16, 17, 18, 19, 23, 25, 26, 27];
      final defaultSwitches = isEsp8266
          ? [13, 16, 255, 255, 255, 255, 255, 255]
          : [13, 14, 27, 26, 25, 255, 255, 255];
      final idx = _channels.length;
      final rPin = idx < defaultRelays.length ? defaultRelays[idx] : 255;
      final sPin = idx < defaultSwitches.length ? defaultSwitches[idx] : 255;
      _channels.add(ChannelHardwareConfig(
        enabled: true,
        switchEnabled: (sPin != 255),
        relayPin: rPin,
        switchPin: sPin,
        switchMode: SwitchMode.toggle,
        triggerMode: 0,
      ));
    });
  }

  void _removeChannel() {
    if (_numRelays <= 0) return;
    setState(() {
      _isCustomMode = true;
      _numRelays--;
      if (_channels.isNotEmpty) {
        _channels.removeLast();
      }
    });
  }

  void _applyPreset(String preset) {
    setState(() {
      _isCustomMode = false;
      _boardNameController.text = preset;
      final isEsp8266 = widget.device.isEsp8266;

      if (isEsp8266) {
        if (preset.contains('1-CH')) {
          _numRelays = 1;
          _channels = [
            const ChannelHardwareConfig(relayPin: 12, switchPin: 13, switchMode: SwitchMode.pushbutton, triggerMode: 0)
          ];
          _dhtType = ClimateSensorType.none;
          _dhtPin = 255;
          _mq2Enabled = false;
          _buzzerEnabled = false;
          _lcdEnabled = false;
        } else if (preset.contains('2-CH')) {
          _numRelays = 2;
          _channels = [
            const ChannelHardwareConfig(relayPin: 12, switchPin: 13, switchMode: SwitchMode.toggle, triggerMode: 0),
            const ChannelHardwareConfig(relayPin: 14, switchPin: 16, switchMode: SwitchMode.toggle, triggerMode: 0),
          ];
          _dhtType = ClimateSensorType.dht22;
          _dhtPin = 4;
          _mq2Enabled = true;
          _mq2AnalogPin = 17;
          _buzzerEnabled = true;
          _buzzerPin = 2;
          _lcdEnabled = false;
        } else if (preset.contains('3-CH')) {
          _numRelays = 3;
          _channels = [
            const ChannelHardwareConfig(relayPin: 12, switchPin: 13, switchMode: SwitchMode.toggle, triggerMode: 0),
            const ChannelHardwareConfig(relayPin: 14, switchPin: 16, switchMode: SwitchMode.toggle, triggerMode: 0),
            const ChannelHardwareConfig(relayPin: 4, switchPin: 255, switchMode: SwitchMode.toggle, triggerMode: 0),
          ];
          _dhtType = ClimateSensorType.none;
          _dhtPin = 255;
          _mq2Enabled = true;
          _mq2AnalogPin = 17;
          _buzzerEnabled = true;
          _buzzerPin = 2;
          _lcdEnabled = false;
        } else if (preset.contains('4-CH')) {
          _numRelays = 4;
          _channels = [
            const ChannelHardwareConfig(relayPin: 12, switchPin: 13, switchMode: SwitchMode.toggle, triggerMode: 0),
            const ChannelHardwareConfig(relayPin: 14, switchPin: 16, switchMode: SwitchMode.toggle, triggerMode: 0),
            const ChannelHardwareConfig(relayPin: 4, switchPin: 255, switchMode: SwitchMode.toggle, triggerMode: 0),
            const ChannelHardwareConfig(relayPin: 5, switchPin: 255, switchMode: SwitchMode.toggle, triggerMode: 0),
          ];
          _dhtType = ClimateSensorType.none;
          _dhtPin = 255;
          _mq2Enabled = true;
          _mq2AnalogPin = 17;
          _buzzerEnabled = true;
          _buzzerPin = 2;
          _lcdEnabled = false;
        } else if (preset.contains('8-CH')) {
          _numRelays = 8;
          final rPins = [12, 14, 4, 5, 13, 15, 0, 16];
          _channels = List.generate(8, (i) => ChannelHardwareConfig(
            enabled: true,
            switchEnabled: false,
            relayPin: rPins[i],
            switchPin: 255,
            switchMode: SwitchMode.toggle,
            triggerMode: 0,
          ));
          _dhtType = ClimateSensorType.none;
          _dhtPin = 255;
          _mq2Enabled = true;
          _mq2AnalogPin = 17;
          _buzzerEnabled = true;
          _buzzerPin = 2;
          _lcdEnabled = false;
        } else if (preset.contains('Sensor Node')) {
          _numRelays = 0;
          _channels = [];
          _dhtType = ClimateSensorType.bme280;
          _dhtPin = 255;
          _i2cSdaPin = 4;
          _i2cSclPin = 5;
          _mq2Enabled = true;
          _mq2AnalogPin = 17;
          _buzzerEnabled = true;
          _buzzerPin = 2;
          _lcdEnabled = true;
        }
      } else {
        // ESP32 Presets
        if (preset.contains('1-CH')) {
          _numRelays = 1;
          _channels = [
            const ChannelHardwareConfig(relayPin: 16, switchPin: 13, switchMode: SwitchMode.pushbutton, triggerMode: 0)
          ];
          _dhtType = ClimateSensorType.dht22;
          _dhtPin = 4;
          _mq2Enabled = false;
          _buzzerEnabled = false;
          _lcdEnabled = false;
        } else if (preset.contains('2-CH')) {
          _numRelays = 2;
          _channels = [
            const ChannelHardwareConfig(relayPin: 16, switchPin: 13, switchMode: SwitchMode.toggle, triggerMode: 0),
            const ChannelHardwareConfig(relayPin: 17, switchPin: 14, switchMode: SwitchMode.toggle, triggerMode: 0),
          ];
          _dhtType = ClimateSensorType.dht22;
          _dhtPin = 4;
          _mq2Enabled = true;
          _buzzerEnabled = true;
          _lcdEnabled = true;
        } else if (preset.contains('4-CH')) {
          _numRelays = 4;
          _channels = [
            const ChannelHardwareConfig(relayPin: 16, switchPin: 13, switchMode: SwitchMode.toggle, triggerMode: 0),
            const ChannelHardwareConfig(relayPin: 17, switchPin: 14, switchMode: SwitchMode.toggle, triggerMode: 0),
            const ChannelHardwareConfig(relayPin: 18, switchPin: 27, switchMode: SwitchMode.toggle, triggerMode: 0),
            const ChannelHardwareConfig(relayPin: 19, switchPin: 26, switchMode: SwitchMode.toggle, triggerMode: 0),
          ];
          _dhtType = ClimateSensorType.dht22;
          _dhtPin = 4;
          _mq2Enabled = true;
          _buzzerEnabled = true;
          _lcdEnabled = true;
        } else if (preset.contains('8-CH')) {
          _numRelays = 8;
          final rPins = [16, 17, 18, 19, 23, 25, 26, 27];
          _channels = List.generate(8, (i) => ChannelHardwareConfig(
            enabled: true,
            switchEnabled: false,
            relayPin: rPins[i],
            switchPin: 255,
            switchMode: SwitchMode.toggle,
            triggerMode: 0,
          ));
          _dhtType = ClimateSensorType.dht22;
          _dhtPin = 4;
          _mq2Enabled = false;
          _buzzerEnabled = true;
          _lcdEnabled = true;
        } else if (preset.contains('Sensor Node')) {
          _numRelays = 0;
          _channels = [];
          _dhtType = ClimateSensorType.dht22;
          _dhtPin = 4;
          _mq2Enabled = true;
          _mq2AnalogPin = 34;
          _buzzerEnabled = true;
          _buzzerPin = 5;
          _lcdEnabled = true;
        } else {
          // 5-CH Standard
          _numRelays = 5;
          _initDefaultChannels(5);
          _dhtType = ClimateSensorType.dht22;
          _dhtPin = 4;
          _mq2Enabled = true;
          _mq2AnalogPin = 34;
          _buzzerEnabled = true;
          _buzzerPin = 5;
          _lcdEnabled = true;
        }
      }
    });
  }

  Map<int, String> _getUsedPins() {
    final Map<int, String> used = {};
    for (int i = 0; i < _numRelays && i < _channels.length; i++) {
      if (_channels[i].enabled && _channels[i].relayPin != 255) {
        used[_channels[i].relayPin] = 'Relay ${i + 1}';
      }
      if (_channels[i].switchEnabled && _channels[i].switchPin != 255) {
        used[_channels[i].switchPin] = 'Switch ${i + 1}';
      }
    }
    if ((_dhtType == ClimateSensorType.dht11 || _dhtType == ClimateSensorType.dht22) && _dhtPin != 255) {
      used[_dhtPin] = 'DHT Climate';
    }
    if (_motionType != MotionSensorType.none && _motionPin != 255) {
      used[_motionPin] = 'Motion';
    }
    if (_probeType != ProbeSensorType.none && _probePin != 255) {
      used[_probePin] = 'DS18B20';
    }
    if (_ultrasonicType != UltrasonicSensorType.none) {
      if (_trigPin != 255) used[_trigPin] = 'Trig';
      if (_echoPin != 255) used[_echoPin] = 'Echo';
    }
    if (_mq2Enabled) {
      if (_mq2AnalogPin != 255) used[_mq2AnalogPin] = 'MQ-2 (A)';
      if (_mq2DigitalPin != 255) used[_mq2DigitalPin] = 'MQ-2 (D)';
    }
    if (_buzzerEnabled && _buzzerPin != 255) {
      used[_buzzerPin] = 'Buzzer';
    }
    final bool isI2cActive = _lcdEnabled ||
        _dhtType == ClimateSensorType.bme280 ||
        _dhtType == ClimateSensorType.aht20 ||
        _dhtType == ClimateSensorType.sht31 ||
        _lightType == LightSensorType.bh1750;
    if (isI2cActive) {
      if (_i2cSdaPin != 255) used[_i2cSdaPin] = 'I2C SDA';
      if (_i2cSclPin != 255) used[_i2cSclPin] = 'I2C SCL';
    }
    if (_btnMultiPin != 255) {
      used[_btnMultiPin] = 'Status Button';
    }
    return used;
  }

  String? _findConflict() {
    final isEsp8266 = widget.device.isEsp8266;
    final inOnly = HardwareProfile.inputOnlyPinsFor(isEsp8266);
    final Map<int, String> used = {};

    void claim(int pin, String name, {bool isOutput = false}) {
      if (pin == 255) return;
      if (isOutput && inOnly.contains(pin)) {
        throw 'GPIO $pin is an input-only pin and cannot be used for output ($name)';
      }
      if (used.containsKey(pin)) {
        throw 'GPIO $pin is assigned to both "${used[pin]}" and "$name"';
      }
      used[pin] = name;
    }

    try {
      for (int i = 0; i < _numRelays && i < _channels.length; i++) {
        if (!_channels[i].enabled) continue;
        claim(_channels[i].relayPin, 'Relay ${i + 1}', isOutput: true);
        if (_channels[i].switchEnabled) {
          claim(_channels[i].switchPin, 'Switch ${i + 1}', isOutput: false);
        }
      }
      if (_dhtType == ClimateSensorType.dht11 || _dhtType == ClimateSensorType.dht22) {
        claim(_dhtPin, 'DHT Climate', isOutput: true);
      }
      if (_motionType != MotionSensorType.none) {
        claim(_motionPin, 'Motion Sensor', isOutput: false);
      }
      if (_probeType != ProbeSensorType.none) {
        claim(_probePin, 'DS18B20 Probe', isOutput: true);
      }
      if (_ultrasonicType != UltrasonicSensorType.none) {
        claim(_trigPin, 'Ultrasonic Trig', isOutput: true);
        claim(_echoPin, 'Ultrasonic Echo', isOutput: false);
      }
      if (_mq2Enabled) {
        claim(_mq2AnalogPin, 'MQ-2 Analog', isOutput: false);
        claim(_mq2DigitalPin, 'MQ-2 Digital', isOutput: false);
      }
      if (_buzzerEnabled) {
        claim(_buzzerPin, 'Buzzer', isOutput: true);
      }
      final bool isI2cActive = _lcdEnabled ||
          _dhtType == ClimateSensorType.bme280 ||
          _dhtType == ClimateSensorType.aht20 ||
          _dhtType == ClimateSensorType.sht31 ||
          _lightType == LightSensorType.bh1750;
      if (isI2cActive) {
        claim(_i2cSdaPin, 'I2C SDA', isOutput: true);
        claim(_i2cSclPin, 'I2C SCL', isOutput: true);
      }
      claim(_btnMultiPin, 'Multi-Button', isOutput: false);
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Widget _buildPinMatrix() {
    final isEsp8266 = widget.device.isEsp8266;
    final allPins = HardwareProfile.allPhysicalPinsFor(isEsp8266);
    final strapping = HardwareProfile.strappingPinsFor(isEsp8266);
    final inOnly = HardwareProfile.inputOnlyPinsFor(isEsp8266);
    final used = _getUsedPins();
    final conflict = _findConflict();

    int usedCount = 0;
    for (final p in allPins) {
      if (used.containsKey(p)) usedCount++;
    }
    final freeCount = allPins.length - usedCount;

    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'LIVE GPIO PIN ALLOCATION MATRIX',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textSecondary,
                  letterSpacing: 0.8,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      '$usedCount/${allPins.length} Used',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primary),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.success.withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      '$freeCount Free',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.success),
                    ),
                  ),
                  if (conflict != null) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.danger.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.danger),
                      ),
                      child: Text(
                        'Conflict!',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.danger),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: allPins.map((pin) {
              final isAssigned = used.containsKey(pin);
              final assignedName = used[pin];
              final isBoot = strapping.contains(pin);
              final isInOnly = inOnly.contains(pin);
              final isConflict = conflict != null && conflict.contains('GPIO $pin ');

              Color borderColor = isConflict
                  ? AppColors.danger
                  : (isAssigned ? AppColors.accent.withValues(alpha: 0.6) : Colors.white12);
              Color bgColor = isConflict
                  ? AppColors.danger.withValues(alpha: 0.2)
                  : (isAssigned ? AppColors.accent.withValues(alpha: 0.1) : AppColors.surface);

              return Container(
                width: 105,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: borderColor, width: isConflict ? 1.5 : 1.0),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          pin == 17 && isEsp8266 ? 'A0' : 'GPIO $pin',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isAssigned ? AppColors.textPrimary : AppColors.textSecondary,
                          ),
                        ),
                        if (isBoot)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: AppColors.warning.withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'Boot',
                              style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppColors.warning),
                            ),
                          )
                        else if (isInOnly)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.white12,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'In',
                              style: TextStyle(fontSize: 9, color: AppColors.textSecondary),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      isAssigned ? assignedName! : 'Free',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: isAssigned ? FontWeight.w600 : FontWeight.normal,
                        color: isConflict
                            ? AppColors.danger
                            : (isAssigned ? AppColors.accent : AppColors.success),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Future<void> _saveAndReboot() async {
    final conflict = _findConflict();
    if (conflict != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(conflict),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Save & Apply Hardware Profile?'),
        content: Text(
          'This will configure $_numRelays active relay(s), update GPIO pin mappings, and reboot the controller.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save & Reboot'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isSaving = true);

    final profile = HardwareProfile(
      boardName: _boardNameController.text.trim().isEmpty
          ? 'Custom'
          : _boardNameController.text.trim(),
      numRelays: _numRelays,
      channels: _channels.sublist(0, _numRelays),
      dhtType: _dhtType,
      dhtPin: _dhtPin,
      lightType: _lightType,
      motionType: _motionType,
      motionPin: _motionPin,
      probeType: _probeType,
      probePin: _probePin,
      ultrasonicType: _ultrasonicType,
      trigPin: _trigPin,
      echoPin: _echoPin,
      tankDepthCm: int.tryParse(_tankDepthController.text) ?? 150,
      tankAirGapCm: int.tryParse(_tankAirGapController.text) ?? 15,
      mq2Enabled: _mq2Enabled,
      mq2AnalogPin: _mq2AnalogPin,
      mq2DigitalPin: _mq2DigitalPin,
      buzzerEnabled: _buzzerEnabled,
      buzzerPin: _buzzerPin,
      lcdEnabled: _lcdEnabled,
      lcdI2cAddr: _lcdI2cAddr,
      lcdCols: _lcdCols,
      lcdRows: _lcdRows,
      i2cSdaPin: _i2cSdaPin,
      i2cSclPin: _i2cSclPin,
      btnMultiPin: _btnMultiPin,
    );

    final ok = await widget.manager.apiClient.saveHardwareProfile(
      widget.device.ip,
      profile,
      password: widget.device.authPassword,
      username: widget.device.authUsername,
    );

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (ok) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Hardware profile applied! Controller is rebooting...'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to save hardware profile. Check connection or authorization.'),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final conflict = _findConflict();

    return Container(
      height: MediaQuery.of(context).size.height * 0.90,
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.developer_board, color: AppColors.primary, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Hardware Profile & GPIO Engine',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        '${widget.device.name} • Tasmota-Style Configuration',
                        style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close, color: AppColors.textSecondary),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.white12),

          if (_isLoading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_errorMessage != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
                      ),
                      child: const Text(
                        'Could not fetch live profile from controller. Loaded defaults.',
                        style: TextStyle(color: AppColors.warning, fontSize: 13),
                      ),
                    ),

                  if (conflict != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                        color: AppColors.danger.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.danger),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded, color: AppColors.danger, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              conflict,
                              style: const TextStyle(color: Colors.redAccent, fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Mode Switcher: Smart Presets vs Custom DIY Mode
                  Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () => setState(() => _isCustomMode = false),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: !_isCustomMode ? AppColors.primary : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              alignment: Alignment.center,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.bolt, size: 16, color: !_isCustomMode ? Colors.white : AppColors.textSecondary),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Smart Presets',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: !_isCustomMode ? Colors.white : AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: InkWell(
                            onTap: () => setState(() => _isCustomMode = true),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: _isCustomMode ? AppColors.accent : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              alignment: Alignment.center,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.tune, size: 16, color: _isCustomMode ? Colors.black : AppColors.textSecondary),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Custom DIY Mode',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: _isCustomMode ? Colors.black : AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Presets Card or DIY Mode Info Card
                  if (!_isCustomMode)
                    GlassCard(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'BOARD TEMPLATES & PRESETS',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textSecondary, letterSpacing: 0.8),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: HardwareProfile.presetsFor(widget.device.isEsp8266).map((preset) {
                              final isSelected = _boardNameController.text == preset;
                              return ChoiceChip(
                                label: Text(preset, style: TextStyle(fontSize: 12, color: isSelected ? Colors.white : AppColors.textSecondary)),
                                selected: isSelected,
                                selectedColor: AppColors.primary,
                                backgroundColor: AppColors.surface,
                                onSelected: (_) => _applyPreset(preset),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    )
                  else
                    GlassCard(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppColors.accent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(Icons.handyman, color: AppColors.accent, size: 22),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Custom DIY Hardware Mode Active',
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.accent),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Add up to 8 relays and connect any sensors according to physical pin budget. The matrix below tracks pin safety.',
                                  style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 14),

                  // Live GPIO Pin Matrix
                  _buildPinMatrix(),
                  const SizedBox(height: 14),

                  GlassCard(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: _boardNameController,
                          style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
                          decoration: InputDecoration(
                            labelText: 'Board Template Name',
                            labelStyle: TextStyle(color: AppColors.textSecondary),
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Active Relay Channels:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                            Row(
                              children: [
                                Text('$_numRelays / 8', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary, fontSize: 14)),
                                const SizedBox(width: 10),
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    side: BorderSide(color: AppColors.primary.withValues(alpha: 0.5)),
                                  ),
                                  icon: Icon(Icons.add, size: 14, color: AppColors.primary),
                                  label: Text('Add', style: TextStyle(fontSize: 12, color: AppColors.primary)),
                                  onPressed: _numRelays < 8 ? _addChannel : null,
                                ),
                                const SizedBox(width: 6),
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    side: const BorderSide(color: Colors.white24),
                                  ),
                                  icon: const Icon(Icons.remove, size: 14, color: Colors.white70),
                                  label: const Text('Remove', style: TextStyle(fontSize: 12, color: Colors.white70)),
                                  onPressed: _numRelays > 0 ? _removeChannel : null,
                                ),
                              ],
                            ),
                          ],
                        ),
                        Slider(
                          value: _numRelays.toDouble(),
                          min: 0,
                          max: 8,
                          divisions: 8,
                          activeColor: AppColors.primary,
                          label: '$_numRelays Channels',
                          onChanged: (val) {
                            setState(() {
                              _isCustomMode = true;
                              _numRelays = val.toInt();
                              final isEsp8266 = widget.device.isEsp8266;
                              final defaultRelays = isEsp8266
                                  ? [12, 14, 4, 5, 13, 15, 0, 16]
                                  : [16, 17, 18, 19, 23, 25, 26, 27];
                              final defaultSwitches = isEsp8266
                                  ? [13, 16, 255, 255, 255, 255, 255, 255]
                                  : [13, 14, 27, 26, 25, 255, 255, 255];
                              while (_channels.length < _numRelays) {
                                final idx = _channels.length;
                                final sPin = idx < defaultSwitches.length ? defaultSwitches[idx] : 255;
                                final rPin = idx < defaultRelays.length ? defaultRelays[idx] : 255;
                                _channels.add(ChannelHardwareConfig(
                                  enabled: true,
                                  switchEnabled: (sPin != 255),
                                  relayPin: rPin,
                                  switchPin: sPin,
                                  switchMode: SwitchMode.toggle,
                                  triggerMode: 0,
                                ));
                              }
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  if (_numRelays > 0) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                      child: Text(
                        'RELAY & WALL SWITCH CHANNELS',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textSecondary, letterSpacing: 0.8),
                      ),
                    ),
                    for (int i = 0; i < _numRelays && i < _channels.length; i++)
                      _buildChannelCard(i),
                    const SizedBox(height: 14),
                  ],

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    child: Text(
                      'SENSORS & PERIPHERALS',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textSecondary, letterSpacing: 0.8),
                    ),
                  ),

                  // Climate Sensor
                  GlassCard(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Climate & Environmental Sensor', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.accent)),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<ClimateSensorType>(
                                key: ValueKey('dht_type_${_dhtType.value}'),
                                isExpanded: true,
                                initialValue: _dhtType,
                                decoration: const InputDecoration(labelText: 'Sensor Model', border: OutlineInputBorder(), isDense: true),
                                items: ClimateSensorType.values.map((t) => DropdownMenuItem(value: t, child: Text(t.label, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)))).toList(),
                                onChanged: (val) => setState(() => _dhtType = val ?? ClimateSensorType.none),
                              ),
                            ),
                            if (_dhtType == ClimateSensorType.dht11 || _dhtType == ClimateSensorType.dht22) ...[
                              const SizedBox(width: 10),
                              Expanded(
                                child: _buildPinDropdown('Data Pin', _dhtPin, HardwareProfile.outputPinsFor(widget.device.isEsp8266), (p) => setState(() => _dhtPin = p)),
                              ),
                            ],
                          ],
                        ),
                        if (_dhtType.value >= 3) ...[
                          const SizedBox(height: 6),
                          Text('Uses shared I2C bus (SDA: ${HardwareProfile.pinLabel(_i2cSdaPin, widget.device.isEsp8266)}, SCL: ${HardwareProfile.pinLabel(_i2cSclPin, widget.device.isEsp8266)}). No data pin needed.', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Ambient Light (Optics)
                  GlassCard(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Ambient Light Sensor (Optics)', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.accent)),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<LightSensorType>(
                          key: ValueKey('light_type_${_lightType.value}'),
                          isExpanded: true,
                          initialValue: _lightType,
                          decoration: const InputDecoration(labelText: 'Sensor Model', border: OutlineInputBorder(), isDense: true),
                          items: LightSensorType.values.map((t) => DropdownMenuItem(value: t, child: Text(t.label, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)))).toList(),
                          onChanged: (val) => setState(() => _lightType = val ?? LightSensorType.none),
                        ),
                        if (_lightType != LightSensorType.none) ...[
                          const SizedBox(height: 6),
                          Text('Uses shared I2C bus (SDA: GPIO 21, SCL: GPIO 22).', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Motion / Occupancy
                  GlassCard(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Motion & Occupancy Sensor', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.accent)),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<MotionSensorType>(
                                key: ValueKey('motion_type_${_motionType.value}'),
                                isExpanded: true,
                                initialValue: _motionType,
                                decoration: const InputDecoration(labelText: 'Sensor Type', border: OutlineInputBorder(), isDense: true),
                                items: MotionSensorType.values.map((t) => DropdownMenuItem(value: t, child: Text(t.label, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)))).toList(),
                                onChanged: (val) => setState(() => _motionType = val ?? MotionSensorType.none),
                              ),
                            ),
                            if (_motionType != MotionSensorType.none) ...[
                              const SizedBox(width: 10),
                              Expanded(
                                child: _buildPinDropdown('Digital Signal Pin', _motionPin, HardwareProfile.inputPinsFor(widget.device.isEsp8266), (p) => setState(() => _motionPin = p)),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Submersible Water Temp Probe
                  GlassCard(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Water Temperature Probe (DS18B20)', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.accent)),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<ProbeSensorType>(
                                key: ValueKey('probe_type_${_probeType.value}'),
                                isExpanded: true,
                                initialValue: _probeType,
                                decoration: const InputDecoration(labelText: 'Probe Status', border: OutlineInputBorder(), isDense: true),
                                items: ProbeSensorType.values.map((t) => DropdownMenuItem(value: t, child: Text(t.label, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)))).toList(),
                                onChanged: (val) => setState(() => _probeType = val ?? ProbeSensorType.none),
                              ),
                            ),
                            if (_probeType != ProbeSensorType.none) ...[
                              const SizedBox(width: 10),
                              Expanded(
                                child: _buildPinDropdown('1-Wire Pin (Needs 4.7kΩ Pull-up)', _probePin, HardwareProfile.outputPinsFor(widget.device.isEsp8266), (p) => setState(() => _probePin = p)),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Ultrasonic Distance & Overhead Water Tank
                  GlassCard(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Ultrasonic Distance & Water Tank Monitor', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.accent)),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<UltrasonicSensorType>(
                          key: ValueKey('ultrasonic_type_${_ultrasonicType.value}'),
                          isExpanded: true,
                          initialValue: _ultrasonicType,
                          decoration: const InputDecoration(labelText: 'Module Model', border: OutlineInputBorder(), isDense: true),
                          items: UltrasonicSensorType.values.map((t) => DropdownMenuItem(value: t, child: Text(t.label, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)))).toList(),
                          onChanged: (val) => setState(() => _ultrasonicType = val ?? UltrasonicSensorType.none),
                        ),
                        if (_ultrasonicType != UltrasonicSensorType.none) ...[
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: _buildPinDropdown('Trig GPIO Pin', _trigPin, HardwareProfile.outputPinsFor(widget.device.isEsp8266), (p) => setState(() => _trigPin = p)),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _buildPinDropdown('Echo GPIO Pin', _echoPin, HardwareProfile.inputPinsFor(widget.device.isEsp8266), (p) => setState(() => _echoPin = p)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _tankDepthController,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(labelText: 'Tank Total Depth (cm)', border: OutlineInputBorder(), isDense: true),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TextField(
                                  controller: _tankAirGapController,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(labelText: 'Sensor Air Gap (cm)', border: OutlineInputBorder(), isDense: true),
                                ),
                              ),
                            ],
                          ),
                          if (_ultrasonicType == UltrasonicSensorType.hcsr04) ...[
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.warning.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AppColors.warning.withValues(alpha: 0.5)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 18),
                                      const SizedBox(width: 6),
                                      Text(
                                        'WARNING: Electrical Safety Precaution (5V to 3.3V):',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.warning,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '• The standard blue HC-SR04 is powered by 5V, so its ECHO pin sends a 5V signal.\n'
                                    '• The ESP32\'s GPIO pins are rated for 3.3V.\n'
                                    '• Best Practice: Place a simple two-resistor voltage divider (e.g. 1kΩ and 2kΩ) on the ECHO line before connecting it to GPIO 35 to safely step the voltage down from 5V to ~3.3V.\n'
                                    '• Alternative: If you use the newer HC-SR04P or the waterproof JSN-SR04T module, it runs directly at 3.3V with no resistors needed.',
                                    style: TextStyle(fontSize: 11, height: 1.4, color: AppColors.textPrimary),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          if (_ultrasonicType == UltrasonicSensorType.hcsr04p) ...[
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppColors.success.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AppColors.success.withValues(alpha: 0.4)),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.check_circle_outline, color: AppColors.success, size: 16),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      '3.3V Safe: HC-SR04P operates directly at 3.3V logic. Plug-and-play connection to ESP32 with no resistors needed.',
                                      style: TextStyle(fontSize: 11, color: AppColors.textPrimary),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),

                  // MQ-2 Gas
                  GlassCard(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Gas & Smoke Sensor (MQ-2)', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.warning)),
                            Switch(
                              value: _mq2Enabled,
                              activeThumbColor: AppColors.warning,
                              onChanged: (val) => setState(() => _mq2Enabled = val),
                            ),
                          ],
                        ),
                        if (_mq2Enabled) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: _buildPinDropdown('Analog A0 (ADC1)', _mq2AnalogPin, HardwareProfile.adc1PinsFor(widget.device.isEsp8266), (p) => setState(() => _mq2AnalogPin = p), allowNone: false),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _buildPinDropdown('Digital D0', _mq2DigitalPin, HardwareProfile.inputPinsFor(widget.device.isEsp8266), (p) => setState(() => _mq2DigitalPin = p), allowNone: true),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Buzzer
                  GlassCard(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(widget.device.isEsp8266 ? 'Alarm Buzzer (ESP8266 PWM)' : 'Alarm Buzzer (LEDC PWM)', style: const TextStyle(fontWeight: FontWeight.bold)),
                            Switch(
                              value: _buzzerEnabled,
                              activeThumbColor: AppColors.primary,
                              onChanged: (val) => setState(() => _buzzerEnabled = val),
                            ),
                          ],
                        ),
                        if (_buzzerEnabled) ...[
                          const SizedBox(height: 8),
                          _buildPinDropdown('Buzzer GPIO Pin', _buzzerPin, HardwareProfile.outputPinsFor(widget.device.isEsp8266), (p) => setState(() => _buzzerPin = p), allowNone: false),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),

                  // LCD
                  GlassCard(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('I2C LCD Display', style: TextStyle(fontWeight: FontWeight.bold)),
                            Switch(
                              value: _lcdEnabled,
                              activeThumbColor: AppColors.primary,
                              onChanged: (val) => setState(() => _lcdEnabled = val),
                            ),
                          ],
                        ),
                        if (_lcdEnabled) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<int>(
                                  key: ValueKey('lcd_addr_$_lcdI2cAddr'),
                                  isExpanded: true,
                                  initialValue: _lcdI2cAddr,
                                  decoration: const InputDecoration(labelText: 'I2C Address', border: OutlineInputBorder(), isDense: true),
                                  items: const [
                                    DropdownMenuItem(value: 39, child: Text('0x27 (Standard)', overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12))),
                                    DropdownMenuItem(value: 63, child: Text('0x3F', overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12))),
                                  ],
                                  onChanged: (val) => setState(() => _lcdI2cAddr = val ?? 39),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  key: ValueKey('lcd_rows_$_lcdRows'),
                                  isExpanded: true,
                                  initialValue: _lcdRows == 4 ? '20x4' : '16x2',
                                  decoration: const InputDecoration(labelText: 'Display Size', border: OutlineInputBorder(), isDense: true),
                                  items: const [
                                    DropdownMenuItem(value: '16x2', child: Text('16 x 2', overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12))),
                                    DropdownMenuItem(value: '20x4', child: Text('20 x 4', overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12))),
                                  ],
                                  onChanged: (val) => setState(() {
                                    if (val == '20x4') {
                                      _lcdCols = 20;
                                      _lcdRows = 4;
                                    } else {
                                      _lcdCols = 16;
                                      _lcdRows = 2;
                                    }
                                  }),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: _buildPinDropdown('SDA Pin', _i2cSdaPin, HardwareProfile.outputPinsFor(widget.device.isEsp8266), (p) => setState(() => _i2cSdaPin = p), allowNone: false),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _buildPinDropdown('SCL Pin', _i2cSclPin, HardwareProfile.outputPinsFor(widget.device.isEsp8266), (p) => setState(() => _i2cSclPin = p), allowNone: false),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Multi-button
                  GlassCard(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Multi-Function Status Button', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        _buildPinDropdown('Button GPIO Pin (INPUT_PULLUP)', _btnMultiPin, HardwareProfile.inputPinsFor(widget.device.isEsp8266), (p) => setState(() => _btnMultiPin = p), allowNone: true),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),

          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: const Border(top: BorderSide(color: Colors.white12)),
              ),
              child: Row(
                children: [
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                    ),
                    onPressed: _isSaving ? null : () => _applyPreset('SmartHome 5-CH Standard'),
                    child: const Text('Reset 5-CH', maxLines: 1),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: conflict == null ? AppColors.primary : Colors.grey,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                      icon: _isSaving
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.check_circle_outline, size: 18),
                      label: Text(
                        _isSaving ? 'Saving & Rebooting...' : 'Save & Reboot Controller',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onPressed: (_isSaving || conflict != null) ? null : _saveAndReboot,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChannelCard(int i) {
    final ch = _channels[i];
    final isChEn = ch.enabled;
    final isSwEn = isChEn && ch.switchEnabled;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isChEn ? AppColors.cardBorder : AppColors.danger.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text('Channel ${i + 1}', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary, fontSize: 13)),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isChEn ? AppColors.success.withValues(alpha: 0.15) : AppColors.danger.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      isChEn ? 'ACTIVE' : 'DISABLED',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: isChEn ? AppColors.success : AppColors.danger,
                      ),
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Text('Channel:', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                  const SizedBox(width: 4),
                  Transform.scale(
                    scale: 0.75,
                    child: Switch(
                      value: isChEn,
                      activeThumbColor: AppColors.primary,
                      onChanged: (val) {
                        setState(() {
                          _channels[i] = ch.copyWith(enabled: val);
                        });
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Opacity(
            opacity: isChEn ? 1.0 : 0.4,
            child: IgnorePointer(
              ignoring: !isChEn,
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _buildPinDropdown('Relay GPIO', ch.relayPin, HardwareProfile.outputPinsFor(widget.device.isEsp8266), (pin) {
                          setState(() {
                            _channels[i] = ch.copyWith(relayPin: pin);
                          });
                        }, allowNone: false),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          key: ValueKey('ch_${i}_trig_${ch.triggerMode}'),
                          isExpanded: true,
                          initialValue: ch.triggerMode,
                          decoration: const InputDecoration(labelText: 'Trigger', border: OutlineInputBorder(), isDense: true),
                          items: const [
                            DropdownMenuItem(value: 0, child: Text('Active LOW', overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12))),
                            DropdownMenuItem(value: 1, child: Text('Active HIGH', overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12))),
                          ],
                          onChanged: (val) => setState(() => _channels[i] = ch.copyWith(triggerMode: val ?? 0)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Wall Switch:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                      Row(
                        children: [
                          Text(isSwEn ? 'Enabled' : 'Disabled', style: TextStyle(fontSize: 11, color: isSwEn ? AppColors.success : AppColors.textSecondary)),
                          const SizedBox(width: 4),
                          Transform.scale(
                            scale: 0.7,
                            child: Switch(
                              value: isSwEn,
                              activeThumbColor: AppColors.accent,
                              onChanged: !isChEn ? null : (val) {
                                setState(() {
                                  _channels[i] = ch.copyWith(switchEnabled: val);
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Opacity(
                    opacity: isSwEn ? 1.0 : 0.4,
                    child: IgnorePointer(
                      ignoring: !isSwEn,
                      child: Row(
                        children: [
                          Expanded(
                            child: _buildPinDropdown('Switch GPIO', ch.switchPin, HardwareProfile.inputPinsFor(widget.device.isEsp8266), (pin) {
                              setState(() {
                                _channels[i] = ch.copyWith(switchPin: pin);
                              });
                            }, allowNone: true),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: DropdownButtonFormField<SwitchMode>(
                              key: ValueKey('ch_${i}_mode_${ch.switchMode.value}'),
                              isExpanded: true,
                              initialValue: ch.switchMode,
                              decoration: const InputDecoration(labelText: 'Switch Mode', border: OutlineInputBorder(), isDense: true),
                              items: SwitchMode.values.map((m) => DropdownMenuItem(value: m, child: Text(m.label, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)))).toList(),
                              onChanged: (val) => setState(() => _channels[i] = ch.copyWith(switchMode: val ?? SwitchMode.toggle)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPinDropdown(
    String label,
    int selectedPin,
    List<int> pins,
    ValueChanged<int> onChanged, {
    bool allowNone = true,
  }) {
    final items = <DropdownMenuItem<int>>[];
    if (allowNone) {
      items.add(DropdownMenuItem(value: 255, child: Text(HardwareProfile.pinLabel(255, widget.device.isEsp8266), overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12))));
    }
    for (final p in pins) {
      final pinLabel = HardwareProfile.pinLabel(p, widget.device.isEsp8266);
      items.add(DropdownMenuItem(value: p, child: Text(pinLabel, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12))));
    }

    final hasPin = items.any((item) => item.value == selectedPin);
    final val = hasPin ? selectedPin : (allowNone ? 255 : (pins.isNotEmpty ? pins.first : 255));

    return DropdownButtonFormField<int>(
      key: ValueKey('pin_${label}_$val'),
      isExpanded: true,
      initialValue: val,
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true),
      items: items,
      onChanged: (newVal) {
        if (newVal != null) onChanged(newVal);
      },
    );
  }
}
