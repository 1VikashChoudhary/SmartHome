import 'dart:math' as math;
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

  List<ClimateSensorSlotConfig> _climates = [
    const ClimateSensorSlotConfig(type: ClimateSensorType.dht22, pin: 4),
  ];
  List<LightSensorSlotConfig> _lights = [];
  List<MotionSensorSlotConfig> _motions = [];
  List<ProbeSensorSlotConfig> _probes = [];
  List<UltrasonicSensorSlotConfig> _ultrasonics = [];
  final List<TextEditingController> _tankDepthControllers = [];
  final List<TextEditingController> _tankAirGapControllers = [];
  List<Mq2SensorSlotConfig> _mq2s = [
    const Mq2SensorSlotConfig(enabled: true, analogPin: 34, digitalPin: 35),
  ];
  SensorLimitsConfig _sensorLimits = const SensorLimitsConfig();
  int _formGeneration = 0;

  bool get _hasAnyI2cSensor =>
      _climates.any((c) => c.type.isI2c) ||
      _lights.any((l) => l.type != LightSensorType.none) ||
      _mq2s.any((g) => g.enabled && g.type.isI2c);

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
      _climates = [];
      _lights = [];
      _motions = [];
      _probes = [];
      _ultrasonics = [];
      _mq2s = [
        const Mq2SensorSlotConfig(enabled: true, analogPin: 17, digitalPin: 255),
      ];
      _buzzerPin = 2;
      _i2cSdaPin = 4;
      _i2cSclPin = 5;
      _btnMultiPin = 0;
    }
    _boardNameController = TextEditingController(
      text: widget.device.isEsp8266 ? 'SmartHome ESP8266 2-CH Dual' : 'SmartHome 5-CH Standard',
    );
    _syncUltrasonicControllers();
    _loadHardwareProfile();
  }

  void _syncUltrasonicControllers() {
    while (_tankDepthControllers.length > _ultrasonics.length) {
      _tankDepthControllers.removeLast().dispose();
    }
    while (_tankAirGapControllers.length > _ultrasonics.length) {
      _tankAirGapControllers.removeLast().dispose();
    }
    for (int i = 0; i < _ultrasonics.length; i++) {
      final depthText = _ultrasonics[i].tankDepthCm.toString();
      final gapText = _ultrasonics[i].tankAirGapCm.toString();
      if (i >= _tankDepthControllers.length) {
        _tankDepthControllers.add(TextEditingController(text: depthText));
      } else if (_tankDepthControllers[i].text != depthText) {
        _tankDepthControllers[i].text = depthText;
      }
      if (i >= _tankAirGapControllers.length) {
        _tankAirGapControllers.add(TextEditingController(text: gapText));
      } else if (_tankAirGapControllers[i].text != gapText) {
        _tankAirGapControllers[i].text = gapText;
      }
    }
  }

  @override
  void dispose() {
    _boardNameController.dispose();
    for (final c in _tankDepthControllers) {
      c.dispose();
    }
    for (final c in _tankAirGapControllers) {
      c.dispose();
    }
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

      if (!mounted) return;

      if (profile != null) {
        _applyProfileToState(profile);
      } else {
        final defaultCount = widget.device.isEsp8266 ? 2 : 5;
        _initDefaultChannels(defaultCount);
      }
    } catch (_) {
      if (!mounted) return;
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

    _sensorLimits = p.sensorLimits;
    _climates = List<ClimateSensorSlotConfig>.from(p.climates);
    _lights = List<LightSensorSlotConfig>.from(p.lights);
    _motions = List<MotionSensorSlotConfig>.from(p.motions);
    _probes = List<ProbeSensorSlotConfig>.from(p.probes);
    _ultrasonics = List<UltrasonicSensorSlotConfig>.from(p.ultrasonics);
    _mq2s = List<Mq2SensorSlotConfig>.from(p.mq2Sensors);
    _syncUltrasonicControllers();
    _formGeneration++;
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

  void _switchToCustomModeName() {
    final presets = HardwareProfile.presetsFor(widget.device.isEsp8266);
    if (_boardNameController.text.trim().isEmpty ||
        presets.contains(_boardNameController.text.trim())) {
      _boardNameController.text = widget.device.isEsp8266
          ? 'SmartHome ESP8266 Custom DIY'
          : 'SmartHome Custom DIY Controller';
    }
  }

  void _enterCustomMode() {
    _isCustomMode = true;
    _switchToCustomModeName();
  }

  int _pickFreePin(List<int> candidates, Set<int> usedPins, {int? preferred}) {
    final isEsp8266 = widget.device.isEsp8266;
    final strapping = HardwareProfile.strappingPinsFor(isEsp8266);
    if (preferred != null &&
        preferred != 255 &&
        candidates.contains(preferred) &&
        !usedPins.contains(preferred)) {
      return preferred;
    }
    // Prefer safe non-strapping pins first
    for (final pin in candidates) {
      if (!usedPins.contains(pin) && !strapping.contains(pin)) {
        return pin;
      }
    }
    // Fall back to strapping pins when free GPIO budget is tight
    for (final pin in candidates) {
      if (!usedPins.contains(pin)) {
        return pin;
      }
    }
    return 255;
  }

  ChannelHardwareConfig _allocateChannelForIndex(int idx, Set<int> usedPins) {
    final isEsp8266 = widget.device.isEsp8266;
    final defaultRelays = isEsp8266
        ? [12, 14, 4, 5, 13, 15, 0, 16]
        : [16, 17, 18, 19, 23, 25, 26, 27];
    final defaultSwitches = isEsp8266
        ? [13, 16, 255, 255, 255, 255, 255, 255]
        : [13, 14, 27, 26, 25, 255, 255, 255];

    final preferredRelay = idx < defaultRelays.length ? defaultRelays[idx] : null;
    final rPin = _pickFreePin(
      HardwareProfile.outputPinsFor(isEsp8266),
      usedPins,
      preferred: preferredRelay,
    );
    if (rPin != 255) usedPins.add(rPin);

    final preferredSwitch =
        idx < defaultSwitches.length ? defaultSwitches[idx] : 255;
    int sPin = 255;
    bool swEn = false;
    if (preferredSwitch != 255) {
      sPin = _pickFreePin(
        HardwareProfile.inputPinsFor(isEsp8266),
        usedPins,
        preferred: preferredSwitch,
      );
      if (sPin != 255) {
        usedPins.add(sPin);
        swEn = true;
      }
    }

    return ChannelHardwareConfig(
      enabled: true,
      switchEnabled: swEn,
      relayPin: rPin,
      switchPin: sPin,
      switchMode: SwitchMode.toggle,
      triggerMode: 0,
    );
  }

  void _addChannel() {
    if (_numRelays >= 8) return;
    final usedPins = _getUsedPins().keys.toSet();
    final idx = _numRelays;
    if (_channels.length > _numRelays) {
      _channels.removeRange(_numRelays, _channels.length);
    }
    final newChannel = _allocateChannelForIndex(idx, usedPins);

    setState(() {
      _isCustomMode = true;
      _switchToCustomModeName();
      _channels.add(newChannel);
      _numRelays++;
    });

    if (newChannel.relayPin == 255 && mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Relay Channel ${idx + 1} added with unassigned pin — free a peripheral/switch GPIO or assign a pin.',
          ),
          backgroundColor: AppColors.warning,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _removeChannel() {
    if (_numRelays <= 0) return;
    setState(() {
      _isCustomMode = true;
      _switchToCustomModeName();
      _numRelays--;
      if (_channels.length > _numRelays) {
        _channels.removeRange(_numRelays, _channels.length);
      }
    });
  }

  void _showPinWarning(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.warning,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _ensureI2cBusPins([Set<int>? _]) {
    final isEsp8266 = widget.device.isEsp8266;
    final outputPins = HardwareProfile.outputPinsFor(isEsp8266);
    final nonI2cUsed = _getUsedPins(includeI2cBus: false).keys.toSet();
    if (_i2cSdaPin == 255 || nonI2cUsed.contains(_i2cSdaPin)) {
      final sdaForbidden = {
        ...nonI2cUsed,
        if (_i2cSclPin != 255) _i2cSclPin,
      };
      _i2cSdaPin = _pickFreePin(
        outputPins,
        sdaForbidden,
        preferred: isEsp8266 ? 4 : 21,
      );
    }
    if (_i2cSclPin == 255 ||
        nonI2cUsed.contains(_i2cSclPin) ||
        (_i2cSdaPin != 255 && _i2cSclPin == _i2cSdaPin)) {
      final sclForbidden = {
        ...nonI2cUsed,
        if (_i2cSdaPin != 255) _i2cSdaPin,
      };
      _i2cSclPin = _pickFreePin(
        outputPins,
        sclForbidden,
        preferred: isEsp8266 ? 5 : 22,
      );
    }
  }

  void _addClimateSlot() {
    if (_climates.length >= _sensorLimits.climates) return;
    final isEsp8266 = widget.device.isEsp8266;
    final used = _getUsedPins().keys.toSet();
    final usedI2c = _getUsedI2cAddrs();
    final freePin = _pickFreePin(
      HardwareProfile.outputPinsFor(isEsp8266),
      used,
      preferred: _climates.isEmpty ? (isEsp8266 ? 14 : 4) : null,
    );

    ClimateSensorSlotConfig slot;
    bool unassigned = false;
    if (freePin != 255) {
      slot = ClimateSensorSlotConfig(type: ClimateSensorType.dht22, pin: freePin);
    } else {
      ClimateSensorSlotConfig? i2cSlot;
      for (final model in [
        ClimateSensorType.sht4x,
        ClimateSensorType.bme280,
        ClimateSensorType.sht31,
        ClimateSensorType.aht20,
      ]) {
        for (final addr in model.allowedI2cAddrs) {
          if (!usedI2c.containsKey(addr)) {
            i2cSlot = ClimateSensorSlotConfig(type: model, pin: 255, i2cAddr: addr);
            break;
          }
        }
        if (i2cSlot != null) break;
      }
      if (i2cSlot != null && _i2cSdaPin != 255 && _i2cSclPin != 255) {
        slot = i2cSlot;
      } else {
        slot = const ClimateSensorSlotConfig(type: ClimateSensorType.dht22, pin: 255);
        unassigned = true;
      }
    }

    setState(() {
      _isCustomMode = true;
      _switchToCustomModeName();
      _climates.add(slot);
      if (slot.type.isI2c) _ensureI2cBusPins(used);
    });
    if (unassigned) {
      _showPinWarning('Climate Sensor ${_climates.length} added without free GPIO — switch to an I2C model or free a GPIO.');
    }
  }

  void _addLightSlot() {
    if (_lights.length >= _sensorLimits.lights) return;
    final used = _getUsedPins().keys.toSet();
    final usedI2c = _getUsedI2cAddrs();
    int addr = 0x23;
    bool collision = false;
    if (usedI2c.containsKey(0x23)) {
      if (!usedI2c.containsKey(0x5C)) {
        addr = 0x5C;
      } else {
        collision = true;
      }
    }
    setState(() {
      _isCustomMode = true;
      _switchToCustomModeName();
      _lights.add(LightSensorSlotConfig(type: LightSensorType.bh1750, i2cAddr: addr));
      _ensureI2cBusPins(used);
    });
    if (collision || _i2cSdaPin == 255 || _i2cSclPin == 255) {
      _showPinWarning('Light Sensor ${_lights.length} needs a free I2C address & shared SDA/SCL bus.');
    }
  }

  void _addMotionSlot() {
    if (_motions.length >= _sensorLimits.motions) return;
    final isEsp8266 = widget.device.isEsp8266;
    final used = _getUsedPins().keys.toSet();
    final pin = _pickFreePin(
      HardwareProfile.inputPinsFor(isEsp8266),
      used,
      preferred: _motions.isEmpty ? (isEsp8266 ? 14 : 32) : null,
    );
    setState(() {
      _isCustomMode = true;
      _switchToCustomModeName();
      _motions.add(MotionSensorSlotConfig(type: MotionSensorType.pir, pin: pin));
    });
    if (pin == 255) {
      _showPinWarning('Motion Sensor ${_motions.length} added with unassigned GPIO — free a GPIO or assign one.');
    }
  }

  void _addProbeSlot() {
    if (_probes.length >= _sensorLimits.probes) return;
    final isEsp8266 = widget.device.isEsp8266;
    final used = _getUsedPins().keys.toSet();
    final pin = _pickFreePin(
      HardwareProfile.outputPinsFor(isEsp8266),
      used,
      preferred: _probes.isEmpty ? (isEsp8266 ? 13 : 15) : null,
    );
    setState(() {
      _isCustomMode = true;
      _switchToCustomModeName();
      _probes.add(ProbeSensorSlotConfig(type: ProbeSensorType.ds18b20, pin: pin));
    });
    if (pin == 255) {
      _showPinWarning('Probe ${_probes.length} added with unassigned GPIO — free an output GPIO or assign one.');
    }
  }

  void _addUltrasonicSlot() {
    if (_ultrasonics.length >= _sensorLimits.ultrasonics) return;
    final isEsp8266 = widget.device.isEsp8266;
    final used = _getUsedPins().keys.toSet();
    final trig = _pickFreePin(
      HardwareProfile.outputPinsFor(isEsp8266),
      used,
      preferred: _ultrasonics.isEmpty ? (isEsp8266 ? 14 : 15) : null,
    );
    if (trig != 255) used.add(trig);
    final echo = _pickFreePin(
      HardwareProfile.inputPinsFor(isEsp8266),
      used,
      preferred: _ultrasonics.isEmpty ? (isEsp8266 ? 12 : 35) : null,
    );
    setState(() {
      _isCustomMode = true;
      _switchToCustomModeName();
      _ultrasonics.add(
        UltrasonicSensorSlotConfig(
          type: UltrasonicSensorType.hcsr04p,
          trigPin: trig,
          echoPin: echo,
          tankDepthCm: 150,
          tankAirGapCm: 15,
        ),
      );
      _syncUltrasonicControllers();
    });
    if (trig == 255 || echo == 255) {
      _showPinWarning('Ultrasonic Sensor ${_ultrasonics.length} added with unassigned Trig/Echo GPIO — free pins or assign manually.');
    }
  }

  void _addMq2Slot() {
    if (_mq2s.length >= _sensorLimits.mq2s) return;
    final isEsp8266 = widget.device.isEsp8266;
    final used = _getUsedPins().keys.toSet();
    final aPin = _pickFreePin(
      HardwareProfile.adc1PinsFor(isEsp8266),
      used,
      preferred: _mq2s.isEmpty ? (isEsp8266 ? 17 : 34) : null,
    );
    if (aPin != 255) used.add(aPin);

    int dPin = 255;
    if (aPin == 255) {
      dPin = _pickFreePin(HardwareProfile.inputPinsFor(isEsp8266), used);
    } else if (_mq2s.isEmpty && !isEsp8266) {
      dPin = _pickFreePin(
        HardwareProfile.inputPinsFor(false),
        used,
        preferred: 35,
      );
    }

    if (aPin == 255 && dPin == 255) {
      final usedI2c = _getUsedI2cAddrs();
      if (!usedI2c.containsKey(0x59) &&
          _i2cSdaPin != 255 &&
          _i2cSclPin != 255) {
        setState(() {
          _isCustomMode = true;
          _switchToCustomModeName();
          _mq2s.add(
            const Mq2SensorSlotConfig(
              type: GasSensorType.sgp40,
              enabled: true,
              analogPin: 255,
              digitalPin: 255,
              i2cAddr: 0x59,
            ),
          );
          _ensureI2cBusPins();
        });
        return;
      }
    }

    setState(() {
      _isCustomMode = true;
      _switchToCustomModeName();
      _mq2s.add(
        Mq2SensorSlotConfig(enabled: true, analogPin: aPin, digitalPin: dPin),
      );
    });
    if (aPin == 255 && dPin == 255) {
      _showPinWarning('MQ-2 Sensor ${_mq2s.length} added without free Analog or Digital GPIO.');
    }
  }

  void _removeSensorSlot<T>(
    List<T> list,
    int index, {
    VoidCallback? after,
  }) {
    if (index < 0 || index >= list.length) return;
    setState(() {
      _isCustomMode = true;
      _switchToCustomModeName();
      list.removeAt(index);
      _formGeneration++;
      after?.call();
    });
  }

  void _applyPreset(String preset) {
    setState(() {
      _isCustomMode = false;
      _boardNameController.text = preset;
      final isEsp8266 = widget.device.isEsp8266;

      // Reset optional add-on sensors & LCD display geometry before applying preset specifics
      _lcdI2cAddr = 39;
      _lcdCols = 16;
      _lcdRows = 2;
      _climates = [];
      _lights = [];
      _motions = [];
      _probes = [];
      _ultrasonics = [];
      _mq2s = [];

      if (isEsp8266) {
        if (preset.contains('1-CH')) {
          _numRelays = 1;
          _channels = [
            const ChannelHardwareConfig(relayPin: 12, switchPin: 13, switchMode: SwitchMode.pushbutton, triggerMode: 0)
          ];
          _climates = [
            const ClimateSensorSlotConfig(type: ClimateSensorType.dht22, pin: 14),
          ];
          _mq2s = [
            const Mq2SensorSlotConfig(enabled: true, analogPin: 17, digitalPin: 255),
          ];
          _buzzerEnabled = true;
          _buzzerPin = 2;
          _lcdEnabled = true;
          _i2cSdaPin = 4;
          _i2cSclPin = 5;
          _btnMultiPin = 0;
        } else if (preset.contains('3-CH')) {
          _numRelays = 3;
          _channels = [
            const ChannelHardwareConfig(relayPin: 12, switchPin: 13, switchMode: SwitchMode.toggle, triggerMode: 0),
            const ChannelHardwareConfig(relayPin: 14, switchPin: 16, switchMode: SwitchMode.toggle, triggerMode: 0),
            const ChannelHardwareConfig(relayPin: 15, switchPin: 255, switchEnabled: false, switchMode: SwitchMode.toggle, triggerMode: 0),
          ];
          _mq2s = [
            const Mq2SensorSlotConfig(enabled: true, analogPin: 17, digitalPin: 255),
          ];
          _buzzerEnabled = true;
          _buzzerPin = 2;
          _lcdEnabled = true;
          _i2cSdaPin = 4;
          _i2cSclPin = 5;
          _btnMultiPin = 0;
        } else if (preset.contains('4-CH')) {
          _numRelays = 4;
          _channels = [
            const ChannelHardwareConfig(relayPin: 12, switchPin: 13, switchMode: SwitchMode.toggle, triggerMode: 0),
            const ChannelHardwareConfig(relayPin: 14, switchPin: 16, switchMode: SwitchMode.toggle, triggerMode: 0),
            const ChannelHardwareConfig(relayPin: 4, switchPin: 255, switchEnabled: false, switchMode: SwitchMode.toggle, triggerMode: 0),
            const ChannelHardwareConfig(relayPin: 5, switchPin: 255, switchEnabled: false, switchMode: SwitchMode.toggle, triggerMode: 0),
          ];
          _mq2s = [
            const Mq2SensorSlotConfig(enabled: true, analogPin: 17, digitalPin: 255),
          ];
          _buzzerEnabled = true;
          _buzzerPin = 2;
          _lcdEnabled = false;
          _i2cSdaPin = 255;
          _i2cSclPin = 255;
          _btnMultiPin = 0;
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
          _mq2s = [
            const Mq2SensorSlotConfig(enabled: true, analogPin: 17, digitalPin: 255),
          ];
          _buzzerEnabled = true;
          _buzzerPin = 2;
          _lcdEnabled = false;
          _i2cSdaPin = 255;
          _i2cSclPin = 255;
          _btnMultiPin = 255;
        } else if (preset.contains('Sensor Node')) {
          _numRelays = 0;
          _channels = [];
          _climates = [
            const ClimateSensorSlotConfig(type: ClimateSensorType.dht22, pin: 12),
          ];
          _motions = [
            const MotionSensorSlotConfig(type: MotionSensorType.pir, pin: 14),
          ];
          _probes = [
            const ProbeSensorSlotConfig(type: ProbeSensorType.ds18b20, pin: 13),
          ];
          _mq2s = [
            const Mq2SensorSlotConfig(enabled: true, analogPin: 17, digitalPin: 255),
          ];
          _buzzerEnabled = true;
          _buzzerPin = 2;
          _lcdEnabled = true;
          _i2cSdaPin = 4;
          _i2cSclPin = 5;
          _btnMultiPin = 0;
        } else {
          // 2-CH Dual (Default ESP8266)
          _numRelays = 2;
          _channels = [
            const ChannelHardwareConfig(relayPin: 12, switchPin: 13, switchMode: SwitchMode.toggle, triggerMode: 0),
            const ChannelHardwareConfig(relayPin: 14, switchPin: 16, switchMode: SwitchMode.toggle, triggerMode: 0),
          ];
          _mq2s = [
            const Mq2SensorSlotConfig(enabled: true, analogPin: 17, digitalPin: 255),
          ];
          _buzzerEnabled = true;
          _buzzerPin = 2;
          _lcdEnabled = true;
          _i2cSdaPin = 4;
          _i2cSclPin = 5;
          _btnMultiPin = 0;
        }
      } else {
        // ESP32 Presets
        if (preset.contains('1-CH')) {
          _numRelays = 1;
          _channels = [
            const ChannelHardwareConfig(relayPin: 16, switchPin: 13, switchMode: SwitchMode.pushbutton, triggerMode: 0)
          ];
          _climates = [
            const ClimateSensorSlotConfig(type: ClimateSensorType.dht22, pin: 4),
          ];
          _buzzerEnabled = false;
          _buzzerPin = 255;
          _lcdEnabled = false;
          _i2cSdaPin = 255;
          _i2cSclPin = 255;
          _btnMultiPin = 33;
        } else if (preset.contains('2-CH')) {
          _numRelays = 2;
          _channels = [
            const ChannelHardwareConfig(relayPin: 16, switchPin: 13, switchMode: SwitchMode.toggle, triggerMode: 0),
            const ChannelHardwareConfig(relayPin: 17, switchPin: 14, switchMode: SwitchMode.toggle, triggerMode: 0),
          ];
          _climates = [
            const ClimateSensorSlotConfig(type: ClimateSensorType.dht22, pin: 4),
          ];
          _mq2s = [
            const Mq2SensorSlotConfig(enabled: true, analogPin: 34, digitalPin: 35),
          ];
          _buzzerEnabled = true;
          _buzzerPin = 5;
          _lcdEnabled = true;
          _i2cSdaPin = 21;
          _i2cSclPin = 22;
          _btnMultiPin = 33;
        } else if (preset.contains('4-CH')) {
          _numRelays = 4;
          _channels = [
            const ChannelHardwareConfig(relayPin: 16, switchPin: 13, switchMode: SwitchMode.toggle, triggerMode: 0),
            const ChannelHardwareConfig(relayPin: 17, switchPin: 14, switchMode: SwitchMode.toggle, triggerMode: 0),
            const ChannelHardwareConfig(relayPin: 18, switchPin: 27, switchMode: SwitchMode.toggle, triggerMode: 0),
            const ChannelHardwareConfig(relayPin: 19, switchPin: 26, switchMode: SwitchMode.toggle, triggerMode: 0),
          ];
          _climates = [
            const ClimateSensorSlotConfig(type: ClimateSensorType.dht22, pin: 4),
          ];
          _mq2s = [
            const Mq2SensorSlotConfig(enabled: true, analogPin: 34, digitalPin: 35),
          ];
          _buzzerEnabled = true;
          _buzzerPin = 5;
          _lcdEnabled = true;
          _i2cSdaPin = 21;
          _i2cSclPin = 22;
          _btnMultiPin = 33;
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
          _climates = [
            const ClimateSensorSlotConfig(type: ClimateSensorType.dht22, pin: 4),
          ];
          _buzzerEnabled = true;
          _buzzerPin = 5;
          _lcdEnabled = true;
          _i2cSdaPin = 21;
          _i2cSclPin = 22;
          _btnMultiPin = 33;
        } else if (preset.contains('Sensor Node')) {
          _numRelays = 0;
          _channels = [];
          _climates = [
            const ClimateSensorSlotConfig(type: ClimateSensorType.dht22, pin: 4),
          ];
          _mq2s = [
            const Mq2SensorSlotConfig(enabled: true, analogPin: 34, digitalPin: 35),
          ];
          _buzzerEnabled = true;
          _buzzerPin = 5;
          _lcdEnabled = true;
          _i2cSdaPin = 21;
          _i2cSclPin = 22;
          _btnMultiPin = 33;
        } else {
          // 5-CH Standard
          _numRelays = 5;
          _initDefaultChannels(5);
          _climates = [
            const ClimateSensorSlotConfig(type: ClimateSensorType.dht22, pin: 4),
          ];
          _mq2s = [
            const Mq2SensorSlotConfig(enabled: true, analogPin: 34, digitalPin: 35),
          ];
          _buzzerEnabled = true;
          _buzzerPin = 5;
          _lcdEnabled = true;
          _i2cSdaPin = 21;
          _i2cSclPin = 22;
          _btnMultiPin = 33;
        }
      }
      _syncUltrasonicControllers();
      _formGeneration++;
    });
  }

  Map<int, String> _getUsedPins({bool includeI2cBus = true}) {
    final Map<int, String> used = {};
    for (int i = 0; i < _numRelays && i < _channels.length; i++) {
      if (_channels[i].enabled && _channels[i].relayPin != 255) {
        used[_channels[i].relayPin] = 'Relay ${i + 1}';
      }
      if (_channels[i].enabled && _channels[i].switchEnabled && _channels[i].switchPin != 255) {
        used[_channels[i].switchPin] = 'Switch ${i + 1}';
      }
    }
    for (int i = 0; i < _climates.length; i++) {
      final c = _climates[i];
      if (c.type.isOneWire && c.pin != 255) {
        used[c.pin] = 'Climate ${i + 1}';
      }
    }
    for (int i = 0; i < _motions.length; i++) {
      final m = _motions[i];
      if (m.type != MotionSensorType.none && m.pin != 255) {
        used[m.pin] = 'Motion ${i + 1}';
      }
    }
    for (int i = 0; i < _probes.length; i++) {
      final p = _probes[i];
      if (p.type != ProbeSensorType.none && p.pin != 255) {
        used[p.pin] = 'Probe ${i + 1}';
      }
    }
    for (int i = 0; i < _ultrasonics.length; i++) {
      final u = _ultrasonics[i];
      if (u.type != UltrasonicSensorType.none) {
        if (u.trigPin != 255) used[u.trigPin] = 'Trig ${i + 1}';
        if (u.echoPin != 255) used[u.echoPin] = 'Echo ${i + 1}';
      }
    }
    for (int i = 0; i < _mq2s.length; i++) {
      final g = _mq2s[i];
      if (g.enabled && !g.type.isI2c) {
        if (g.analogPin != 255) used[g.analogPin] = 'MQ-2 ${i + 1} (A)';
        if (g.digitalPin != 255) used[g.digitalPin] = 'MQ-2 ${i + 1} (D)';
      }
    }
    if (_buzzerEnabled && _buzzerPin != 255) {
      used[_buzzerPin] = 'Buzzer';
    }
    if (includeI2cBus && (_lcdEnabled || _hasAnyI2cSensor)) {
      if (_i2cSdaPin != 255) used[_i2cSdaPin] = 'I2C SDA';
      if (_i2cSclPin != 255) used[_i2cSclPin] = 'I2C SCL';
    }
    if (_btnMultiPin != 255) {
      used[_btnMultiPin] = 'Status Button';
    }
    return used;
  }

  Map<int, String> _getUsedI2cAddrs({
    int? excludeClimateIndex,
    int? excludeLightIndex,
    int? excludeMq2Index,
  }) {
    final Map<int, String> addrs = {};
    if (_lcdEnabled && _lcdI2cAddr > 0) {
      addrs[_lcdI2cAddr] = 'I2C LCD';
    }
    for (int i = 0; i < _climates.length; i++) {
      if (i == excludeClimateIndex) continue;
      final c = _climates[i];
      if (c.type.isI2c) {
        final addr = c.i2cAddr > 0 ? c.i2cAddr : c.type.defaultI2cAddr;
        if (addr > 0) addrs[addr] = 'Climate ${i + 1}';
      }
    }
    for (int i = 0; i < _lights.length; i++) {
      if (i == excludeLightIndex) continue;
      final l = _lights[i];
      if (l.type != LightSensorType.none) {
        final addr = l.i2cAddr > 0 ? l.i2cAddr : 0x23;
        addrs[addr] = 'Light ${i + 1}';
      }
    }
    for (int i = 0; i < _mq2s.length; i++) {
      if (i == excludeMq2Index) continue;
      final g = _mq2s[i];
      if (g.enabled && g.type.isI2c) {
        final addr = g.i2cAddr > 0 ? g.i2cAddr : 0x59;
        addrs[addr] = 'Air Quality ${i + 1}';
      }
    }
    return addrs;
  }

  String? _findConflict() {
    final isEsp8266 = widget.device.isEsp8266;
    final inOnly = HardwareProfile.inputOnlyPinsFor(isEsp8266);
    final Map<int, String> used = {};
    final Map<int, String> usedI2c = {};

    void claim(
      int pin,
      String name, {
      bool isOutput = false,
      bool isAdc = false,
    }) {
      if (pin == 255) return;
      if (isEsp8266 && pin == 17 && !isAdc) {
        throw 'A0 (GPIO 17) on ESP8266 is analog-only and cannot be used for digital I/O ($name)';
      }
      if (isOutput && inOnly.contains(pin)) {
        throw 'GPIO $pin is an input-only pin and cannot be used for output ($name)';
      }
      if (used.containsKey(pin)) {
        throw 'GPIO $pin is assigned to both "${used[pin]}" and "$name"';
      }
      used[pin] = name;
    }

    void claimI2c(int addr, String name) {
      if (addr <= 0) return;
      if (usedI2c.containsKey(addr)) {
        final hex = '0x${addr.toRadixString(16).toUpperCase().padLeft(2, '0')}';
        throw 'I2C address $hex is assigned to both "${usedI2c[addr]}" and "$name"';
      }
      usedI2c[addr] = name;
    }

    try {
      for (int i = 0; i < _numRelays && i < _channels.length; i++) {
        if (!_channels[i].enabled) continue;
        if (_channels[i].relayPin == 255) {
          throw 'Relay ${i + 1} is enabled but has no Relay GPIO assigned';
        }
        claim(_channels[i].relayPin, 'Relay ${i + 1}', isOutput: true);
        if (_channels[i].switchEnabled) {
          if (_channels[i].switchPin == 255) {
            throw 'Switch ${i + 1} is enabled but has no Switch GPIO assigned';
          }
          claim(_channels[i].switchPin, 'Switch ${i + 1}', isOutput: false);
        }
      }
      for (int i = 0; i < _climates.length; i++) {
        final c = _climates[i];
        final name = 'Climate Sensor ${i + 1}';
        if (c.type.isOneWire) {
          if (c.pin == 255) throw '$name (${c.type.label}) has no Data Pin assigned';
          claim(c.pin, name, isOutput: true);
        } else if (c.type.isI2c) {
          final addr = c.i2cAddr > 0 ? c.i2cAddr : c.type.defaultI2cAddr;
          if (!c.type.allowedI2cAddrs.contains(addr)) {
            throw '$name has an invalid I2C address selected';
          }
          claimI2c(addr, name);
        }
      }
      for (int i = 0; i < _lights.length; i++) {
        final l = _lights[i];
        if (l.type != LightSensorType.none) {
          final addr = l.i2cAddr > 0 ? l.i2cAddr : 0x23;
          if (addr != 0x23 && addr != 0x5C) {
            throw 'Light Sensor ${i + 1} has an invalid BH1750 I2C address';
          }
          claimI2c(addr, 'Light Sensor ${i + 1}');
        }
      }
      for (int i = 0; i < _motions.length; i++) {
        final m = _motions[i];
        if (m.type != MotionSensorType.none) {
          if (m.pin == 255) throw 'Motion Sensor ${i + 1} has no Signal Pin assigned';
          claim(m.pin, 'Motion Sensor ${i + 1}', isOutput: false);
        }
      }
      for (int i = 0; i < _probes.length; i++) {
        final p = _probes[i];
        if (p.type != ProbeSensorType.none) {
          if (p.pin == 255) throw 'DS18B20 Probe ${i + 1} has no 1-Wire Pin assigned';
          claim(p.pin, 'DS18B20 Probe ${i + 1}', isOutput: true);
        }
      }
      for (int i = 0; i < _ultrasonics.length; i++) {
        final u = _ultrasonics[i];
        if (u.type != UltrasonicSensorType.none) {
          if (u.trigPin == 255 || u.echoPin == 255) {
            throw 'Ultrasonic Sensor ${i + 1} has unassigned Trig or Echo GPIO';
          }
          final depth = i < _tankDepthControllers.length
              ? int.tryParse(_tankDepthControllers[i].text.trim())
              : u.tankDepthCm;
          final airGap = i < _tankAirGapControllers.length
              ? int.tryParse(_tankAirGapControllers[i].text.trim())
              : u.tankAirGapCm;
          if (depth == null ||
              depth < 20 ||
              depth > 500 ||
              airGap == null ||
              airGap < 5 ||
              airGap > 100 ||
              depth <= airGap) {
            throw 'Ultrasonic ${i + 1} Tank Depth (20–500 cm) must be greater than Air Gap (5–100 cm)';
          }
          claim(u.trigPin, 'Ultrasonic ${i + 1} Trig', isOutput: true);
          claim(u.echoPin, 'Ultrasonic ${i + 1} Echo', isOutput: false);
        }
      }
      for (int i = 0; i < _mq2s.length; i++) {
        final g = _mq2s[i];
        if (g.enabled) {
          if (g.type.isI2c) {
            final addr = g.i2cAddr > 0 ? g.i2cAddr : 0x59;
            claimI2c(addr, 'SGP40 Air Quality ${i + 1}');
          } else {
            if (g.analogPin == 255 && g.digitalPin == 255) {
              throw 'MQ-2 Sensor ${i + 1} has neither Analog nor Digital GPIO assigned';
            }
            if (g.analogPin != 255) {
              claim(g.analogPin, 'MQ-2 ${i + 1} Analog', isOutput: false, isAdc: true);
            }
            if (g.digitalPin != 255) {
              claim(g.digitalPin, 'MQ-2 ${i + 1} Digital', isOutput: false);
            }
          }
        }
      }
      if (_buzzerEnabled) {
        if (_buzzerPin == 255) throw 'Buzzer is enabled but has no GPIO pin selected';
        claim(_buzzerPin, 'Buzzer', isOutput: true);
      }
      if (_lcdEnabled) {
        if (_lcdI2cAddr != 39 && _lcdI2cAddr != 63) {
          throw 'I2C LCD address must be 0x27 or 0x3F';
        }
        claimI2c(_lcdI2cAddr, 'I2C LCD');
      }
      if (_lcdEnabled || _hasAnyI2cSensor) {
        if (_i2cSdaPin == 255 || _i2cSclPin == 255) {
          throw 'I2C Bus is active (LCD/Sensors) but SDA or SCL pin is unassigned';
        }
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
            children: [
              Expanded(
                child: Text(
                  'LIVE GPIO PIN ALLOCATION MATRIX',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textSecondary,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
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
                  if (conflict != null)
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
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              const spacing = 8.0;
              final cols = constraints.maxWidth >= 460
                  ? 4
                  : (constraints.maxWidth >= 260 ? 3 : 2);
              final tileWidth =
                  (constraints.maxWidth - spacing * (cols - 1)) / cols;
              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: allPins.map((pin) {
                  final isAssigned = used.containsKey(pin);
                  final assignedName = used[pin];
                  final isBoot = strapping.contains(pin);
                  final isAdc8266 = isEsp8266 && pin == 17;
                  final isInOnly = inOnly.contains(pin);
                  final isConflict = conflict != null &&
                      RegExp(r'\bGPIO ' + pin.toString() + r'\b').hasMatch(conflict);

                  Color borderColor = isConflict
                      ? AppColors.danger
                      : (isAssigned ? AppColors.accent.withValues(alpha: 0.6) : AppColors.cardBorder);
                  Color bgColor = isConflict
                      ? AppColors.danger.withValues(alpha: 0.2)
                      : (isAssigned ? AppColors.accent.withValues(alpha: 0.1) : AppColors.surface);

                  return Container(
                    width: tileWidth,
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
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
                            Expanded(
                              child: Text(
                                isAdc8266 ? 'A0' : 'GPIO $pin',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                  color: isAssigned ? AppColors.textPrimary : AppColors.textSecondary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            if (isBoot)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: AppColors.warning.withValues(alpha: 0.25),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'Boot',
                                  style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: AppColors.warning),
                                ),
                              )
                            else if (isAdc8266)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: AppColors.accent.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'ADC',
                                  style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: AppColors.accent),
                                ),
                              )
                            else if (isInOnly)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: AppColors.cardBorder.withValues(alpha: 0.5),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'In',
                                  style: TextStyle(fontSize: 8.5, color: AppColors.textSecondary),
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
              );
            },
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

    final int activeSensors =
        _climates.where((c) => c.type != ClimateSensorType.none).length +
        _lights.where((l) => l.type != LightSensorType.none).length +
        _motions.where((m) => m.type != MotionSensorType.none).length +
        _probes.where((p) => p.type != ProbeSensorType.none).length +
        _ultrasonics.where((u) => u.type != UltrasonicSensorType.none).length +
        _mq2s.where((g) => g.enabled).length;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Save & Apply Hardware Profile?'),
        content: Text(
          'This will configure $_numRelays active relay(s) and $activeSensors active sensor(s), update GPIO pin mappings, and reboot the controller.',
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

    if (confirm != true || !mounted) return;

    setState(() => _isSaving = true);

    final savedUltrasonics = List<UltrasonicSensorSlotConfig>.generate(
      _ultrasonics.length,
      (i) {
        final u = _ultrasonics[i];
        final d = i < _tankDepthControllers.length
            ? (int.tryParse(_tankDepthControllers[i].text.trim()) ?? u.tankDepthCm)
            : u.tankDepthCm;
        final g = i < _tankAirGapControllers.length
            ? (int.tryParse(_tankAirGapControllers[i].text.trim()) ?? u.tankAirGapCm)
            : u.tankAirGapCm;
        return u.copyWith(tankDepthCm: d, tankAirGapCm: g);
      },
    );

    final profile = HardwareProfile(
      boardName: _boardNameController.text.trim().isEmpty
          ? 'Custom'
          : _boardNameController.text.trim(),
      numRelays: _numRelays,
      channels: _channels.sublist(0, math.min(_numRelays, _channels.length)),
      climates: List<ClimateSensorSlotConfig>.from(_climates),
      lights: List<LightSensorSlotConfig>.from(_lights),
      motions: List<MotionSensorSlotConfig>.from(_motions),
      probes: List<ProbeSensorSlotConfig>.from(_probes),
      ultrasonics: savedUltrasonics,
      mq2Sensors: List<Mq2SensorSlotConfig>.from(_mq2s),
      sensorLimits: _sensorLimits,
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

    final messenger = ScaffoldMessenger.of(context);
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
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Hardware profile applied! Controller is rebooting...'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      messenger.showSnackBar(
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
                color: AppColors.textMuted.withValues(alpha: 0.35),
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
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
          Divider(height: 1, color: AppColors.cardBorder),

          if (!_isLoading && conflict != null)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
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

                  // Mode Switcher: Smart Presets vs Custom DIY Mode
                  Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.cardBorder),
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
                                  Flexible(
                                    child: Text(
                                      'Smart Presets',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: !_isCustomMode ? Colors.white : AppColors.textSecondary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: InkWell(
                            onTap: () => setState(() {
                              _isCustomMode = true;
                              _switchToCustomModeName();
                            }),
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
                                  Flexible(
                                    child: Text(
                                      'Custom DIY Mode',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: _isCustomMode ? Colors.black : AppColors.textSecondary,
                                      ),
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
                                  'Add up to 8 relays and multiple sensors per group up to physical GPIO, ADC, and I2C address budgets. The live pin matrix below tracks conflicts.',
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
                            const Flexible(
                              child: Text(
                                'Active Relay Channels:',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Row(
                              mainAxisSize: MainAxisSize.min,
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
                                    side: BorderSide(color: AppColors.cardBorder),
                                  ),
                                  icon: Icon(Icons.remove, size: 14, color: AppColors.textSecondary),
                                  label: Text('Remove', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                                  onPressed: _numRelays > 0 ? _removeChannel : null,
                                ),
                              ],
                            ),
                          ],
                        ),
                        Slider(
                          value: _numRelays.toDouble().clamp(0.0, 8.0),
                          min: 0,
                          max: 8,
                          divisions: 8,
                          activeColor: AppColors.primary,
                          label: '$_numRelays Channels',
                          onChanged: (val) {
                            final target = val.toInt().clamp(0, 8);
                            final usedPins = _getUsedPins().keys.toSet();
                            bool hadUnassigned = false;
                            setState(() {
                              _isCustomMode = true;
                              _switchToCustomModeName();
                              if (target < _numRelays) {
                                _numRelays = target;
                                if (_channels.length > target) {
                                  _channels.removeRange(target, _channels.length);
                                }
                              } else if (target > _numRelays) {
                                if (_channels.length > _numRelays) {
                                  _channels.removeRange(_numRelays, _channels.length);
                                }
                                while (_channels.length < target) {
                                  final ch = _allocateChannelForIndex(_channels.length, usedPins);
                                  if (ch.relayPin == 255) hadUnassigned = true;
                                  _channels.add(ch);
                                }
                                _numRelays = target;
                              }
                            });
                            if (hadUnassigned && mounted) {
                              ScaffoldMessenger.of(context).hideCurrentSnackBar();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Some added relay channels have unassigned pins — free peripherals/switches or assign GPIOs.',
                                  ),
                                  backgroundColor: AppColors.warning,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
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
                      'SENSORS & PERIPHERALS (MULTI-INSTANCE)',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textSecondary, letterSpacing: 0.8),
                    ),
                  ),

                  _buildMultiSensorCard(
                    groupKey: 'climates',
                    title: 'Climate & Environmental Sensors',
                    subtitle: 'DHT11 / DHT22 / BME280 / AHT20 / SHT3x / SHT40 / SHT45 / DS18B20',
                    emptyLabel: 'climate sensors',
                    count: _climates.length,
                    limit: _sensorLimits.climates,
                    accentColor: AppColors.accent,
                    onAdd: _addClimateSlot,
                    onRemoveLast: () => _removeSensorSlot(_climates, _climates.length - 1),
                    children: List.generate(_climates.length, _buildClimateSlotCard),
                  ),
                  const SizedBox(height: 10),

                  _buildMultiSensorCard(
                    groupKey: 'lights',
                    title: 'Ambient Light Sensors (Optics)',
                    emptyLabel: 'light sensors',
                    count: _lights.length,
                    limit: _sensorLimits.lights,
                    accentColor: AppColors.accent,
                    onAdd: _addLightSlot,
                    onRemoveLast: () => _removeSensorSlot(_lights, _lights.length - 1),
                    children: List.generate(_lights.length, _buildLightSlotCard),
                  ),
                  const SizedBox(height: 10),

                  _buildMultiSensorCard(
                    groupKey: 'motions',
                    title: 'Motion & Occupancy Sensors',
                    emptyLabel: 'motion sensors',
                    count: _motions.length,
                    limit: _sensorLimits.motions,
                    accentColor: AppColors.accent,
                    onAdd: _addMotionSlot,
                    onRemoveLast: () => _removeSensorSlot(_motions, _motions.length - 1),
                    children: List.generate(_motions.length, _buildMotionSlotCard),
                  ),
                  const SizedBox(height: 10),

                  _buildMultiSensorCard(
                    groupKey: 'probes',
                    title: 'Water Temperature Probes (DS18B20)',
                    emptyLabel: 'water probes',
                    count: _probes.length,
                    limit: _sensorLimits.probes,
                    accentColor: AppColors.accent,
                    onAdd: _addProbeSlot,
                    onRemoveLast: () => _removeSensorSlot(_probes, _probes.length - 1),
                    children: List.generate(_probes.length, _buildProbeSlotCard),
                  ),
                  const SizedBox(height: 10),

                  _buildMultiSensorCard(
                    groupKey: 'ultrasonics',
                    title: 'Ultrasonic Distance & Water Tank Monitors',
                    emptyLabel: 'ultrasonic tank sensors',
                    count: _ultrasonics.length,
                    limit: _sensorLimits.ultrasonics,
                    accentColor: AppColors.accent,
                    onAdd: _addUltrasonicSlot,
                    onRemoveLast: () => _removeSensorSlot(
                      _ultrasonics,
                      _ultrasonics.length - 1,
                      after: _syncUltrasonicControllers,
                    ),
                    children: List.generate(_ultrasonics.length, _buildUltrasonicSlotCard),
                  ),
                  const SizedBox(height: 10),

                  _buildMultiSensorCard(
                    groupKey: 'mq2s',
                    title: 'Gas & Air Quality Sensors (MQ-2 / SGP40)',
                    subtitle: widget.device.isEsp8266
                        ? 'ESP8266 has 1 analog A0 pin; additional MQ-2 slots use digital D0, or SGP40 uses I2C 0x59'
                        : null,
                    emptyLabel: 'gas / air quality sensors',
                    count: _mq2s.length,
                    limit: _sensorLimits.mq2s,
                    accentColor: AppColors.warning,
                    onAdd: _addMq2Slot,
                    onRemoveLast: () => _removeSensorSlot(_mq2s, _mq2s.length - 1),
                    children: List.generate(_mq2s.length, _buildMq2SlotCard),
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
                            Expanded(
                              child: Text(
                                widget.device.isEsp8266 ? 'Alarm Buzzer (ESP8266 PWM)' : 'Alarm Buzzer (LEDC PWM)',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                            Switch(
                              value: _buzzerEnabled,
                              activeThumbColor: AppColors.primary,
                              onChanged: (val) => setState(() {
                                _enterCustomMode();
                                _buzzerEnabled = val;
                                if (val && _buzzerPin == 255) {
                                  final isEsp8266 = widget.device.isEsp8266;
                                  _buzzerPin = _pickFreePin(
                                    HardwareProfile.outputPinsFor(isEsp8266),
                                    _getUsedPins().keys.toSet(),
                                    preferred: isEsp8266 ? 2 : 5,
                                  );
                                }
                              }),
                            ),
                          ],
                        ),
                        if (_buzzerEnabled) ...[
                          const SizedBox(height: 8),
                          _buildPinDropdown('Buzzer GPIO Pin', _buzzerPin, HardwareProfile.outputPinsFor(widget.device.isEsp8266), (p) => setState(() {
                            _enterCustomMode();
                            _buzzerPin = p;
                          }), allowNone: false),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),

                  // LCD & Shared I2C Bus
                  GlassCard(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Expanded(
                              child: Text(
                                'I2C Bus & LCD Display',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                            Switch(
                              value: _lcdEnabled,
                              activeThumbColor: AppColors.primary,
                              onChanged: (val) => setState(() {
                                _enterCustomMode();
                                _lcdEnabled = val;
                                if (val) {
                                  _ensureI2cBusPins();
                                }
                              }),
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
                                  initialValue: (_lcdI2cAddr == 39 || _lcdI2cAddr == 63) ? _lcdI2cAddr : 39,
                                  decoration: const InputDecoration(labelText: 'I2C Address', border: OutlineInputBorder(), isDense: true),
                                  items: const [
                                    DropdownMenuItem(value: 39, child: Text('0x27 (Standard)', overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12))),
                                    DropdownMenuItem(value: 63, child: Text('0x3F', overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12))),
                                  ],
                                  onChanged: (val) => setState(() {
                                    _enterCustomMode();
                                    _lcdI2cAddr = val ?? 39;
                                  }),
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
                                    _enterCustomMode();
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
                        ],
                        if (_lcdEnabled || _hasAnyI2cSensor) ...[
                          if (!_lcdEnabled) ...[
                            const SizedBox(height: 6),
                            Text(
                              'Shared I2C Bus Pins (Active for Climate/Light Sensors)',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: _buildPinDropdown('SDA Pin', _i2cSdaPin, HardwareProfile.outputPinsFor(widget.device.isEsp8266), (p) => setState(() {
                                  _enterCustomMode();
                                  _i2cSdaPin = p;
                                }), allowNone: false),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _buildPinDropdown('SCL Pin', _i2cSclPin, HardwareProfile.outputPinsFor(widget.device.isEsp8266), (p) => setState(() {
                                  _enterCustomMode();
                                  _i2cSclPin = p;
                                }), allowNone: false),
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
                        _buildPinDropdown('Button GPIO Pin (INPUT_PULLUP)', _btnMultiPin, HardwareProfile.inputPinsFor(widget.device.isEsp8266), (p) => setState(() {
                          _enterCustomMode();
                          _btnMultiPin = p;
                        }), allowNone: true),
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
                border: Border(top: BorderSide(color: AppColors.cardBorder)),
              ),
              child: Row(
                children: [
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                    ),
                    onPressed: _isSaving ? null : () => _applyPreset(widget.device.isEsp8266 ? 'SmartHome ESP8266 2-CH Dual' : 'SmartHome 5-CH Standard'),
                    child: Text(widget.device.isEsp8266 ? 'Reset 2-CH' : 'Reset 5-CH', maxLines: 1),
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

  String _formatI2cHex(int addr) =>
      '0x${addr.toRadixString(16).toUpperCase().padLeft(2, '0')}';

  Widget _buildMultiSensorCard({
    required String groupKey,
    required String title,
    String? subtitle,
    required String emptyLabel,
    required int count,
    required int limit,
    required Color accentColor,
    required VoidCallback onAdd,
    required VoidCallback onRemoveLast,
    required List<Widget> children,
  }) {
    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(fontWeight: FontWeight.bold, color: accentColor),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(fontSize: 10.5, color: AppColors.textSecondary),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$count / $limit',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: accentColor,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              OutlinedButton.icon(
                key: ValueKey('add_${groupKey}_btn'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  side: BorderSide(color: accentColor.withValues(alpha: 0.5)),
                ),
                icon: Icon(Icons.add, size: 14, color: accentColor),
                label: Text('Add Sensor', style: TextStyle(fontSize: 11.5, color: accentColor)),
                onPressed: count < limit ? onAdd : null,
              ),
              OutlinedButton.icon(
                key: ValueKey('remove_${groupKey}_btn'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  side: BorderSide(color: AppColors.cardBorder),
                ),
                icon: Icon(Icons.remove, size: 14, color: AppColors.textSecondary),
                label: Text('Remove', style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
                onPressed: count > 0 ? onRemoveLast : null,
              ),
            ],
          ),
          if (children.isEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'No $emptyLabel configured. Tap "+ Add Sensor" above to add up to $limit.',
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
          ] else ...[
            const SizedBox(height: 10),
            ...children,
          ],
        ],
      ),
    );
  }

  Widget _buildSlotContainer({
    required String groupKey,
    required int index,
    required String slotTitle,
    required Color accentColor,
    required VoidCallback onRemove,
    required List<Widget> children,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                slotTitle,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: accentColor,
                ),
              ),
              IconButton(
                key: ValueKey('remove_${groupKey}_$index'),
                icon: Icon(Icons.close, size: 16, color: AppColors.textSecondary),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: 'Remove slot',
                onPressed: onRemove,
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }

  Widget _buildSlotLabelField({
    required String groupKey,
    required int index,
    required String label,
    required ValueChanged<String> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: TextFormField(
        key: ValueKey('${groupKey}_label_${index}_$_formGeneration'),
        initialValue: label,
        maxLength: 15,
        decoration: const InputDecoration(
          labelText: 'Zone / Label (optional)',
          border: OutlineInputBorder(),
          isDense: true,
          counterText: '',
        ),
        style: TextStyle(fontSize: 12, color: AppColors.textPrimary),
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildSharedI2cBusPinRow(bool isEsp8266) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          Expanded(
            child: _buildPinDropdown(
              'I2C SDA Pin (Shared)',
              _i2cSdaPin,
              HardwareProfile.outputPinsFor(isEsp8266),
              (p) => setState(() {
                _enterCustomMode();
                _i2cSdaPin = p;
              }),
              allowNone: false,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _buildPinDropdown(
              'I2C SCL Pin (Shared)',
              _i2cSclPin,
              HardwareProfile.outputPinsFor(isEsp8266),
              (p) => setState(() {
                _enterCustomMode();
                _i2cSclPin = p;
              }),
              allowNone: false,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClimateSlotCard(int i) {
    final c = _climates[i];
    final isEsp8266 = widget.device.isEsp8266;
    final i2cAddrs = c.type.allowedI2cAddrs;
    final selectedAddr = i2cAddrs.contains(c.i2cAddr)
        ? c.i2cAddr
        : c.type.defaultI2cAddr;

    return _buildSlotContainer(
      groupKey: 'climates',
      index: i,
      slotTitle: 'Climate Sensor #${i + 1}',
      accentColor: AppColors.accent,
      onRemove: () => _removeSensorSlot(_climates, i),
      children: [
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<ClimateSensorType>(
                key: ValueKey('climate_type_${i}_${c.type.value}'),
                isExpanded: true,
                initialValue: c.type,
                decoration: const InputDecoration(labelText: 'Sensor Model', border: OutlineInputBorder(), isDense: true),
                items: ClimateSensorType.values
                    .map((t) => DropdownMenuItem(value: t, child: Text(t.label, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12))))
                    .toList(),
                onChanged: (val) => setState(() {
                  _enterCustomMode();
                  final nextType = val ?? ClimateSensorType.none;
                  final used = _getUsedPins().keys.toSet();
                  int nextPin = c.pin;
                  int nextAddr = c.i2cAddr;
                  if (nextType.isOneWire) {
                    nextAddr = 0;
                    if (nextPin == 255) {
                      nextPin = _pickFreePin(
                        HardwareProfile.outputPinsFor(isEsp8266),
                        used,
                        preferred: i == 0 ? (isEsp8266 ? 14 : 4) : null,
                      );
                    }
                    _climates[i] = c.copyWith(type: nextType, pin: nextPin, i2cAddr: nextAddr);
                  } else if (nextType.isI2c) {
                    nextPin = 255;
                    final usedI2c = _getUsedI2cAddrs(excludeClimateIndex: i);
                    if (!nextType.allowedI2cAddrs.contains(nextAddr) ||
                        usedI2c.containsKey(nextAddr)) {
                      nextAddr = nextType.allowedI2cAddrs.firstWhere(
                        (a) => !usedI2c.containsKey(a),
                        orElse: () => nextType.defaultI2cAddr,
                      );
                    }
                    _climates[i] = c.copyWith(type: nextType, pin: nextPin, i2cAddr: nextAddr);
                    _ensureI2cBusPins();
                  } else {
                    nextPin = 255;
                    nextAddr = 0;
                    _climates[i] = c.copyWith(type: nextType, pin: nextPin, i2cAddr: nextAddr);
                  }
                }),
              ),
            ),
            if (c.type.isOneWire) ...[
              const SizedBox(width: 10),
              Expanded(
                child: _buildPinDropdown(
                  'Data Pin',
                  c.pin,
                  HardwareProfile.outputPinsFor(isEsp8266),
                  (p) => setState(() {
                    _enterCustomMode();
                    _climates[i] = c.copyWith(pin: p);
                  }),
                ),
              ),
            ] else if (c.type.isI2c && i2cAddrs.isNotEmpty) ...[
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<int>(
                  key: ValueKey('climate_addr_${i}_$selectedAddr'),
                  isExpanded: true,
                  initialValue: selectedAddr,
                  decoration: const InputDecoration(labelText: 'I2C Address', border: OutlineInputBorder(), isDense: true),
                  items: i2cAddrs
                      .map((a) => DropdownMenuItem(value: a, child: Text(_formatI2cHex(a), overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12))))
                      .toList(),
                  onChanged: (val) => setState(() {
                    _enterCustomMode();
                    _climates[i] = c.copyWith(i2cAddr: val ?? c.type.defaultI2cAddr);
                  }),
                ),
              ),
            ],
          ],
        ),
        if (c.type.isI2c) ...[
          _buildSharedI2cBusPinRow(isEsp8266),
          const SizedBox(height: 6),
          Text(
            'Shared across all I2C sensors & LCD (changing SDA/SCL updates the whole I2C bus).',
            style: TextStyle(fontSize: 10.5, color: AppColors.textSecondary),
          ),
        ],
        _buildSlotLabelField(
          groupKey: 'climates',
          index: i,
          label: c.label,
          onChanged: (v) => _climates[i] = _climates[i].copyWith(label: v.trim()),
        ),
      ],
    );
  }

  Widget _buildLightSlotCard(int i) {
    final l = _lights[i];
    final isEsp8266 = widget.device.isEsp8266;
    final selectedAddr = (l.i2cAddr == 0x23 || l.i2cAddr == 0x5C) ? l.i2cAddr : 0x23;

    return _buildSlotContainer(
      groupKey: 'lights',
      index: i,
      slotTitle: 'Light Sensor #${i + 1}',
      accentColor: AppColors.accent,
      onRemove: () => _removeSensorSlot(_lights, i),
      children: [
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<LightSensorType>(
                key: ValueKey('light_type_${i}_${l.type.value}'),
                isExpanded: true,
                initialValue: l.type,
                decoration: const InputDecoration(labelText: 'Sensor Model', border: OutlineInputBorder(), isDense: true),
                items: LightSensorType.values
                    .map((t) => DropdownMenuItem(value: t, child: Text(t.label, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12))))
                    .toList(),
                onChanged: (val) => setState(() {
                  _enterCustomMode();
                  final nextType = val ?? LightSensorType.none;
                  int nextAddr = 0;
                  if (nextType != LightSensorType.none) {
                    final usedI2c = _getUsedI2cAddrs(excludeLightIndex: i);
                    const allowed = [0x23, 0x5C];
                    if (allowed.contains(l.i2cAddr) &&
                        !usedI2c.containsKey(l.i2cAddr)) {
                      nextAddr = l.i2cAddr;
                    } else {
                      nextAddr = allowed.firstWhere(
                        (a) => !usedI2c.containsKey(a),
                        orElse: () => allowed.first,
                      );
                    }
                  }
                  _lights[i] = l.copyWith(type: nextType, i2cAddr: nextAddr);
                  if (nextType != LightSensorType.none) {
                    _ensureI2cBusPins();
                  }
                }),
              ),
            ),
            if (l.type != LightSensorType.none) ...[
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<int>(
                  key: ValueKey('light_addr_${i}_$selectedAddr'),
                  isExpanded: true,
                  initialValue: selectedAddr,
                  decoration: const InputDecoration(labelText: 'I2C Address', border: OutlineInputBorder(), isDense: true),
                  items: const [
                    DropdownMenuItem(value: 0x23, child: Text('0x23 (ADDR LOW)', overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12))),
                    DropdownMenuItem(value: 0x5C, child: Text('0x5C (ADDR HIGH)', overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12))),
                  ],
                  onChanged: (val) => setState(() {
                    _enterCustomMode();
                    _lights[i] = l.copyWith(i2cAddr: val ?? 0x23);
                  }),
                ),
              ),
            ],
          ],
        ),
        if (l.type != LightSensorType.none) ...[
          _buildSharedI2cBusPinRow(isEsp8266),
          const SizedBox(height: 6),
          Text(
            'Shared across all I2C sensors & LCD (changing SDA/SCL updates the whole I2C bus).',
            style: TextStyle(fontSize: 10.5, color: AppColors.textSecondary),
          ),
        ],
        _buildSlotLabelField(
          groupKey: 'lights',
          index: i,
          label: l.label,
          onChanged: (v) => _lights[i] = _lights[i].copyWith(label: v.trim()),
        ),
      ],
    );
  }

  Widget _buildMotionSlotCard(int i) {
    final m = _motions[i];
    final isEsp8266 = widget.device.isEsp8266;

    return _buildSlotContainer(
      groupKey: 'motions',
      index: i,
      slotTitle: 'Motion Sensor #${i + 1}',
      accentColor: AppColors.accent,
      onRemove: () => _removeSensorSlot(_motions, i),
      children: [
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<MotionSensorType>(
                key: ValueKey('motion_type_${i}_${m.type.value}'),
                isExpanded: true,
                initialValue: m.type,
                decoration: const InputDecoration(labelText: 'Sensor Type', border: OutlineInputBorder(), isDense: true),
                items: MotionSensorType.values
                    .map((t) => DropdownMenuItem(value: t, child: Text(t.label, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12))))
                    .toList(),
                onChanged: (val) => setState(() {
                  _enterCustomMode();
                  final nextType = val ?? MotionSensorType.none;
                  int nextPin = m.pin;
                  if (nextType != MotionSensorType.none && nextPin == 255) {
                    nextPin = _pickFreePin(
                      HardwareProfile.inputPinsFor(isEsp8266),
                      _getUsedPins().keys.toSet(),
                      preferred: i == 0 ? (isEsp8266 ? 14 : 32) : null,
                    );
                  }
                  _motions[i] = m.copyWith(type: nextType, pin: nextPin);
                }),
              ),
            ),
            if (m.type != MotionSensorType.none) ...[
              const SizedBox(width: 10),
              Expanded(
                child: _buildPinDropdown(
                  'Digital Signal Pin',
                  m.pin,
                  HardwareProfile.inputPinsFor(isEsp8266),
                  (p) => setState(() {
                    _enterCustomMode();
                    _motions[i] = m.copyWith(pin: p);
                  }),
                ),
              ),
            ],
          ],
        ),
        _buildSlotLabelField(
          groupKey: 'motions',
          index: i,
          label: m.label,
          onChanged: (v) => _motions[i] = _motions[i].copyWith(label: v.trim()),
        ),
      ],
    );
  }

  Widget _buildProbeSlotCard(int i) {
    final p = _probes[i];
    final isEsp8266 = widget.device.isEsp8266;

    return _buildSlotContainer(
      groupKey: 'probes',
      index: i,
      slotTitle: 'Water Probe #${i + 1}',
      accentColor: AppColors.accent,
      onRemove: () => _removeSensorSlot(_probes, i),
      children: [
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<ProbeSensorType>(
                key: ValueKey('probe_type_${i}_${p.type.value}'),
                isExpanded: true,
                initialValue: p.type,
                decoration: const InputDecoration(labelText: 'Probe Status', border: OutlineInputBorder(), isDense: true),
                items: ProbeSensorType.values
                    .map((t) => DropdownMenuItem(value: t, child: Text(t.label, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12))))
                    .toList(),
                onChanged: (val) => setState(() {
                  _enterCustomMode();
                  final nextType = val ?? ProbeSensorType.none;
                  int nextPin = p.pin;
                  if (nextType != ProbeSensorType.none && nextPin == 255) {
                    nextPin = _pickFreePin(
                      HardwareProfile.outputPinsFor(isEsp8266),
                      _getUsedPins().keys.toSet(),
                      preferred: i == 0 ? (isEsp8266 ? 13 : 15) : null,
                    );
                  }
                  _probes[i] = p.copyWith(type: nextType, pin: nextPin);
                }),
              ),
            ),
            if (p.type != ProbeSensorType.none) ...[
              const SizedBox(width: 10),
              Expanded(
                child: _buildPinDropdown(
                  '1-Wire Pin (Needs 4.7kΩ Pull-up)',
                  p.pin,
                  HardwareProfile.outputPinsFor(isEsp8266),
                  (pin) => setState(() {
                    _enterCustomMode();
                    _probes[i] = p.copyWith(pin: pin);
                  }),
                ),
              ),
            ],
          ],
        ),
        _buildSlotLabelField(
          groupKey: 'probes',
          index: i,
          label: p.label,
          onChanged: (v) => _probes[i] = _probes[i].copyWith(label: v.trim()),
        ),
      ],
    );
  }

  Widget _buildUltrasonicSlotCard(int i) {
    final u = _ultrasonics[i];
    final isEsp8266 = widget.device.isEsp8266;

    return _buildSlotContainer(
      groupKey: 'ultrasonics',
      index: i,
      slotTitle: 'Ultrasonic Tank #${i + 1}',
      accentColor: AppColors.accent,
      onRemove: () => _removeSensorSlot(
        _ultrasonics,
        i,
        after: _syncUltrasonicControllers,
      ),
      children: [
        DropdownButtonFormField<UltrasonicSensorType>(
          key: ValueKey('ultrasonic_type_${i}_${u.type.value}'),
          isExpanded: true,
          initialValue: u.type,
          decoration: const InputDecoration(labelText: 'Module Model', border: OutlineInputBorder(), isDense: true),
          items: UltrasonicSensorType.values
              .map((t) => DropdownMenuItem(value: t, child: Text(t.label, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12))))
              .toList(),
          onChanged: (val) => setState(() {
            _enterCustomMode();
            final nextType = val ?? UltrasonicSensorType.none;
            int trig = u.trigPin;
            int echo = u.echoPin;
            if (nextType != UltrasonicSensorType.none) {
              final used = _getUsedPins().keys.toSet();
              if (trig == 255) {
                trig = _pickFreePin(
                  HardwareProfile.outputPinsFor(isEsp8266),
                  used,
                  preferred: i == 0 ? (isEsp8266 ? 14 : 15) : null,
                );
                if (trig != 255) used.add(trig);
              }
              if (echo == 255) {
                echo = _pickFreePin(
                  HardwareProfile.inputPinsFor(isEsp8266),
                  used,
                  preferred: i == 0 ? (isEsp8266 ? 12 : 35) : null,
                );
              }
            }
            _ultrasonics[i] = u.copyWith(type: nextType, trigPin: trig, echoPin: echo);
          }),
        ),
        if (u.type != UltrasonicSensorType.none) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildPinDropdown(
                  'Trig GPIO Pin',
                  u.trigPin,
                  HardwareProfile.outputPinsFor(isEsp8266),
                  (p) => setState(() {
                    _enterCustomMode();
                    _ultrasonics[i] = u.copyWith(trigPin: p);
                  }),
                  allowNone: false,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildPinDropdown(
                  'Echo GPIO Pin',
                  u.echoPin,
                  HardwareProfile.inputPinsFor(isEsp8266),
                  (p) => setState(() {
                    _enterCustomMode();
                    _ultrasonics[i] = u.copyWith(echoPin: p);
                  }),
                  allowNone: false,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: i < _tankDepthControllers.length ? _tankDepthControllers[i] : null,
                  keyboardType: TextInputType.number,
                  onChanged: (v) {
                    final parsed = int.tryParse(v.trim());
                    if (parsed != null) {
                      _ultrasonics[i] = _ultrasonics[i].copyWith(tankDepthCm: parsed);
                    }
                    setState(() {});
                  },
                  decoration: const InputDecoration(labelText: 'Tank Total Depth (cm)', border: OutlineInputBorder(), isDense: true),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: i < _tankAirGapControllers.length ? _tankAirGapControllers[i] : null,
                  keyboardType: TextInputType.number,
                  onChanged: (v) {
                    final parsed = int.tryParse(v.trim());
                    if (parsed != null) {
                      _ultrasonics[i] = _ultrasonics[i].copyWith(tankAirGapCm: parsed);
                    }
                    setState(() {});
                  },
                  decoration: const InputDecoration(labelText: 'Sensor Air Gap (cm)', border: OutlineInputBorder(), isDense: true),
                ),
              ),
            ],
          ),
          if (u.type == UltrasonicSensorType.hcsr04) ...[
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
                      Expanded(
                        child: Text(
                          'WARNING: Electrical Safety Precaution (5V to 3.3V):',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.warning,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '• The standard blue HC-SR04 is powered by 5V, so its ECHO pin sends a 5V signal.\n'
                    '• The ${isEsp8266 ? 'ESP8266' : 'ESP32'}\'s GPIO pins are rated for 3.3V.\n'
                    '• Best Practice: Place a simple two-resistor voltage divider (e.g. 1kΩ and 2kΩ) on the ECHO line before connecting it to ${isEsp8266 ? 'an input GPIO' : 'GPIO 35'} to safely step the voltage down from 5V to ~3.3V.\n'
                    '• Alternative: If you use the newer HC-SR04P or the waterproof JSN-SR04T module, it runs directly at 3.3V with no resistors needed.',
                    style: TextStyle(fontSize: 11, height: 1.4, color: AppColors.textPrimary),
                  ),
                ],
              ),
            ),
          ],
          if (u.type == UltrasonicSensorType.hcsr04p) ...[
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
                      '3.3V Safe: HC-SR04P operates directly at 3.3V logic. Plug-and-play connection to ${isEsp8266 ? 'ESP8266' : 'ESP32'} with no resistors needed.',
                      style: TextStyle(fontSize: 11, color: AppColors.textPrimary),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
        _buildSlotLabelField(
          groupKey: 'ultrasonics',
          index: i,
          label: u.label,
          onChanged: (v) => _ultrasonics[i] = _ultrasonics[i].copyWith(label: v.trim()),
        ),
      ],
    );
  }

  Widget _buildMq2SlotCard(int i) {
    final g = _mq2s[i];
    final isEsp8266 = widget.device.isEsp8266;

    return _buildSlotContainer(
      groupKey: 'mq2s',
      index: i,
      slotTitle: '${g.type.isI2c ? "SGP40 Air Quality" : "MQ-2 Gas Sensor"} #${i + 1}',
      accentColor: AppColors.warning,
      onRemove: () => _removeSensorSlot(_mq2s, i),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              g.enabled ? 'ACTIVE' : 'DISABLED',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.bold,
                color: g.enabled ? AppColors.success : AppColors.textSecondary,
              ),
            ),
            Switch(
              value: g.enabled,
              activeThumbColor: AppColors.warning,
              onChanged: (val) => setState(() {
                _enterCustomMode();
                int aPin = g.analogPin;
                int dPin = g.digitalPin;
                if (val && !g.type.isI2c && aPin == 255 && dPin == 255) {
                  final used = _getUsedPins().keys.toSet();
                  aPin = _pickFreePin(
                    HardwareProfile.adc1PinsFor(isEsp8266),
                    used,
                    preferred: i == 0 ? (isEsp8266 ? 17 : 34) : null,
                  );
                  if (aPin == 255) {
                    dPin = _pickFreePin(HardwareProfile.inputPinsFor(isEsp8266), used);
                  }
                }
                _mq2s[i] = g.copyWith(enabled: val, analogPin: aPin, digitalPin: dPin);
                if (val && g.type.isI2c) {
                  _ensureI2cBusPins();
                }
              }),
            ),
          ],
        ),
        if (g.enabled) ...[
          const SizedBox(height: 6),
          DropdownButtonFormField<GasSensorType>(
            key: ValueKey('gas_type_${i}_${g.type.value}'),
            isExpanded: true,
            initialValue: g.type,
            decoration: const InputDecoration(
              labelText: 'Sensor Model',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: GasSensorType.values
                .map(
                  (t) => DropdownMenuItem(
                    value: t,
                    child: Text(
                      t.label,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                )
                .toList(),
            onChanged: (val) => setState(() {
              _enterCustomMode();
              final nextType = val ?? GasSensorType.mq2;
              final used = _getUsedPins().keys.toSet();
              int aPin = g.analogPin;
              int dPin = g.digitalPin;
              if (!nextType.isI2c && aPin == 255 && dPin == 255) {
                aPin = _pickFreePin(
                  HardwareProfile.adc1PinsFor(isEsp8266),
                  used,
                  preferred: i == 0 ? (isEsp8266 ? 17 : 34) : null,
                );
                if (aPin == 255) {
                  dPin = _pickFreePin(HardwareProfile.inputPinsFor(isEsp8266), used);
                }
              }
              _mq2s[i] = g.copyWith(
                type: nextType,
                analogPin: aPin,
                digitalPin: dPin,
                i2cAddr: nextType.isI2c ? 0x59 : 0,
              );
              if (nextType.isI2c) {
                _ensureI2cBusPins();
              }
            }),
          ),
          const SizedBox(height: 8),
          if (g.type.isI2c) ...[
            _buildSharedI2cBusPinRow(isEsp8266),
            const SizedBox(height: 6),
            Text(
              'Uses shared I2C bus at 0x59 (changing SDA/SCL updates the whole I2C bus).',
              style: TextStyle(fontSize: 10.5, color: AppColors.textSecondary),
            ),
          ] else ...[
            Row(
              children: [
                Expanded(
                  child: _buildPinDropdown(
                    'Analog A0 (ADC1)',
                    g.analogPin,
                    HardwareProfile.adc1PinsFor(isEsp8266),
                    (p) => setState(() {
                      _enterCustomMode();
                      _mq2s[i] = g.copyWith(analogPin: p);
                    }),
                    allowNone: true,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildPinDropdown(
                    'Digital D0',
                    g.digitalPin,
                    HardwareProfile.inputPinsFor(isEsp8266),
                    (p) => setState(() {
                      _enterCustomMode();
                      _mq2s[i] = g.copyWith(digitalPin: p);
                    }),
                    allowNone: true,
                  ),
                ),
              ],
            ),
            if (isEsp8266 && g.analogPin == 255 && g.digitalPin != 255) ...[
              const SizedBox(height: 6),
              Text(
                'Digital D0 mode active (ESP8266 A0 analog pin is allocated elsewhere).',
                style: TextStyle(fontSize: 10.5, color: AppColors.textSecondary),
              ),
            ],
          ],
        ],
        _buildSlotLabelField(
          groupKey: 'mq2s',
          index: i,
          label: g.label,
          onChanged: (v) => _mq2s[i] = _mq2s[i].copyWith(label: v.trim()),
        ),
      ],
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
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        'Channel ${i + 1}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary, fontSize: 13),
                      ),
                    ),
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
              ),
              const SizedBox(width: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
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
                          _enterCustomMode();
                          int rp = ch.relayPin;
                          if (val && rp == 255) {
                            final isEsp8266 = widget.device.isEsp8266;
                            final defRelays = isEsp8266
                                ? [12, 14, 4, 5, 13, 15, 0, 16]
                                : [16, 17, 18, 19, 23, 25, 26, 27];
                            rp = _pickFreePin(
                              HardwareProfile.outputPinsFor(isEsp8266),
                              _getUsedPins().keys.toSet(),
                              preferred: i < defRelays.length ? defRelays[i] : null,
                            );
                          }
                          _channels[i] = ch.copyWith(enabled: val, relayPin: rp);
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
                            _enterCustomMode();
                            _channels[i] = ch.copyWith(relayPin: pin);
                          });
                        }, allowNone: false),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          key: ValueKey('ch_${i}_trig_${ch.triggerMode}'),
                          isExpanded: true,
                          initialValue: ch.triggerMode == 1 ? 1 : 0,
                          decoration: const InputDecoration(labelText: 'Trigger', border: OutlineInputBorder(), isDense: true),
                          items: const [
                            DropdownMenuItem(value: 0, child: Text('Active LOW', overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12))),
                            DropdownMenuItem(value: 1, child: Text('Active HIGH', overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12))),
                          ],
                          onChanged: (val) => setState(() {
                            _enterCustomMode();
                            _channels[i] = ch.copyWith(triggerMode: val ?? 0);
                          }),
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
                                  _enterCustomMode();
                                  int sp = ch.switchPin;
                                  if (val && sp == 255) {
                                    final isEsp8266 = widget.device.isEsp8266;
                                    final defSwitches = isEsp8266
                                        ? [13, 16, 255, 255, 255, 255, 255, 255]
                                        : [13, 14, 27, 26, 25, 255, 255, 255];
                                    sp = _pickFreePin(
                                      HardwareProfile.inputPinsFor(isEsp8266),
                                      _getUsedPins().keys.toSet(),
                                      preferred: (i < defSwitches.length && defSwitches[i] != 255)
                                          ? defSwitches[i]
                                          : null,
                                    );
                                  }
                                  _channels[i] = ch.copyWith(switchEnabled: val, switchPin: sp);
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
                                _enterCustomMode();
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
                              onChanged: (val) => setState(() {
                                _enterCustomMode();
                                _channels[i] = ch.copyWith(switchMode: val ?? SwitchMode.toggle);
                              }),
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
    } else if (selectedPin == 255) {
      items.add(const DropdownMenuItem(value: 255, child: Text('Select Pin (Unassigned)', overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12))));
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
