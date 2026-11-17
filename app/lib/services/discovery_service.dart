import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:multicast_dns/multicast_dns.dart';
import 'package:network_info_plus/network_info_plus.dart';
import '../core/models/smart_device.dart';
import '../core/network/api_client.dart';

typedef SubnetDiscoveryTarget = ({String name, List<String> addresses});
typedef PortOpenProbe = Future<bool> Function(String ip, Duration timeout);
typedef DeviceHttpProbe =
    Future<SmartDevice?> Function(String ip, {CancelToken? cancelToken});

class DiscoveryService {
  final ApiClient _api;
  final NetworkInfo _netInfo;
  @visibleForTesting
  final Future<List<SubnetDiscoveryTarget>> Function()? interfacesProvider;
  @visibleForTesting
  final Future<String?> Function()? wifiIpProvider;
  @visibleForTesting
  final PortOpenProbe? portOpenProbe;
  @visibleForTesting
  final DeviceHttpProbe? deviceProbe;

  bool _disposed = false;
  CancelToken? _activeCancelToken;
  MDnsClient? _activeMdnsClient;

  DiscoveryService({
    ApiClient? apiClient,
    NetworkInfo? networkInfo,
    this.interfacesProvider,
    this.wifiIpProvider,
    this.portOpenProbe,
    this.deviceProbe,
  }) : _api = apiClient ?? ApiClient(),
       _netInfo = networkInfo ?? NetworkInfo();

  /// Cancel any in-flight discovery probes and release HTTP client sockets.
  void dispose() {
    _disposed = true;
    final token = _activeCancelToken;
    if (token != null && !token.isCancelled) {
      token.cancel('DiscoveryService disposed');
    }
    _activeCancelToken = null;
    try {
      _activeMdnsClient?.stop();
    } catch (_) {}
    _activeMdnsClient = null;
    _api.dispose();
  }

  /// Discover all devices via Windows-safe mDNS and fast multi-interface subnet scan.
  Future<List<SmartDevice>> discoverAll({
    void Function(SmartDevice device)? onDeviceFound,
  }) async {
    if (_disposed) return [];
    final Map<String, SmartDevice> foundMap = {};
    bool isCancelled = false;
    final CancelToken cancelToken = CancelToken();
    _activeCancelToken = cancelToken;
    MDnsClient? scanMdnsClient;

    void cancelScan([String reason = 'Discovery timeout']) {
      isCancelled = true;
      if (!cancelToken.isCancelled) {
        cancelToken.cancel(reason);
      }
      try {
        scanMdnsClient?.stop();
      } catch (_) {}
      scanMdnsClient = null;
    }

    void addDevice(SmartDevice dev) {
      if (isCancelled || _disposed) return;
      final key = (dev.mac.isNotEmpty && dev.mac != '00:00:00:00:00:00')
          ? dev.mac
          : (dev.id.isNotEmpty ? dev.id : dev.ip);
      if (!foundMap.containsKey(key)) {
        foundMap[key] = dev;
        onDeviceFound?.call(dev);
      }
    }

    try {
      await Future.wait([
        _scanMDNS(
          addDevice,
          () => isCancelled || _disposed,
          cancelToken,
          onClientCreated: (client) {
            scanMdnsClient = client;
            _activeMdnsClient = client;
          },
          onClientClosed: (client) {
            if (_activeMdnsClient == client) _activeMdnsClient = null;
            if (scanMdnsClient == client) scanMdnsClient = null;
          },
        ),
        _scanSubnet(addDevice, () => isCancelled || _disposed, cancelToken),
      ]).timeout(
        const Duration(seconds: 8),
        onTimeout: () {
          cancelScan();
          return [];
        },
      );
    } finally {
      cancelScan('Discovery finished');
      if (_activeCancelToken == cancelToken) {
        _activeCancelToken = null;
      }
    }

    return foundMap.values.toList();
  }

  Future<SmartDevice?> _probeHost(String ip, CancelToken cancelToken) {
    final override = deviceProbe;
    if (override != null) return override(ip, cancelToken: cancelToken);
    return _api.probeDiscovery(ip, cancelToken: cancelToken);
  }

  Future<bool> _isPort80Open(String ip, bool Function() isCancelled) async {
    final timeout = const Duration(milliseconds: 650);
    final custom = portOpenProbe;
    if (custom != null) {
      try {
        return await custom(ip, timeout);
      } catch (_) {
        return false;
      }
    }
    Socket? socket;
    try {
      socket = await Socket.connect(ip, 80, timeout: timeout);
      return !isCancelled();
    } catch (_) {
      return false;
    } finally {
      socket?.destroy();
    }
  }

  static bool isVirtualInterfaceName(String name) {
    final lower = name.toLowerCase();
    const virtualTokens = <String>[
      'vethernet',
      'wsl',
      'hyper-v',
      'docker',
      'vmware',
      'virtualbox',
      'vbox',
      'tailscale',
      'zerotier',
      'wireguard',
      'nordlynx',
      'loopback',
      'utun',
      'tun',
      'tap',
    ];
    for (final token in virtualTokens) {
      if (lower.contains(token)) return true;
    }
    return false;
  }

  static bool isPrivateLanIpv4(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return false;
    final octets = <int>[];
    for (final part in parts) {
      final val = int.tryParse(part);
      if (val == null || val < 0 || val > 255) return false;
      octets.add(val);
    }
    final a = octets[0];
    final b = octets[1];
    if (a == 10) return true;
    if (a == 192 && b == 168) return true;
    if (a == 172 && b >= 16 && b <= 31) return true;
    return false;
  }

  static ({List<String> subnets, Set<String> localIps}) resolveLanSubnets({
    required List<SubnetDiscoveryTarget> interfaces,
    String? wifiIp,
  }) {
    final physicalSubnets = <String>{};
    final virtualSubnets = <String>{};
    final localIps = <String>{};

    void addIp(String ip, Set<String> target) {
      final trimmed = ip.trim();
      if (!isPrivateLanIpv4(trimmed)) return;
      localIps.add(trimmed);
      final parts = trimmed.split('.');
      target.add('${parts[0]}.${parts[1]}.${parts[2]}');
    }

    if (wifiIp != null && wifiIp.isNotEmpty) {
      addIp(wifiIp, physicalSubnets);
    }

    for (final iface in interfaces) {
      final target =
          isVirtualInterfaceName(iface.name) ? virtualSubnets : physicalSubnets;
      for (final addr in iface.addresses) {
        addIp(addr, target);
      }
    }

    final subnets = physicalSubnets.isNotEmpty
        ? physicalSubnets.toList()
        : virtualSubnets.toList();
    return (subnets: subnets, localIps: localIps);
  }

  Future<({List<String> subnets, Set<String> localIps})>
  _discoverLocalSubnets() async {
    String? wifiIp;
    try {
      wifiIp = await (wifiIpProvider?.call() ?? _netInfo.getWifiIP());
    } catch (_) {}

    List<SubnetDiscoveryTarget> interfaces = const [];
    try {
      if (interfacesProvider != null) {
        interfaces = await interfacesProvider!();
      } else {
        final rawInterfaces = await NetworkInterface.list(
          type: InternetAddressType.IPv4,
          includeLoopback: false,
          includeLinkLocal: false,
        );
        interfaces = rawInterfaces
            .map(
              (iface) => (
                name: iface.name,
                addresses: iface.addresses.map((a) => a.address).toList(),
              ),
            )
            .toList();
      }
    } catch (_) {}

    return resolveLanSubnets(interfaces: interfaces, wifiIp: wifiIp);
  }

  Future<Iterable<NetworkInterface>> _selectMulticastInterfaces(
    InternetAddressType type,
  ) async {
    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      includeLinkLocal: false,
      type: type,
    );
    final physical = interfaces.where(
      (i) => i.addresses.isNotEmpty && !isVirtualInterfaceName(i.name),
    );
    if (physical.isNotEmpty) return physical;
    return interfaces.where((i) => i.addresses.isNotEmpty);
  }

  /// 1. Pure Dart mDNS Zero-Conf Scan (_smarthome._tcp)
  ///
  /// Uses `reusePort: false` on Windows because `SO_REUSEPORT` throws
  /// `SocketException (errno = 10042)` on Windows Winsock.
  Future<void> _scanMDNS(
    void Function(SmartDevice) onFound,
    bool Function() isCancelled,
    CancelToken cancelToken, {
    required void Function(MDnsClient) onClientCreated,
    required void Function(MDnsClient) onClientClosed,
  }) async {
    if (interfacesProvider != null || portOpenProbe != null) {
      // Deterministic unit tests pass local subnet/port probes without live UDP 5353.
      return;
    }
    MDnsClient? client;
    bool started = false;
    try {
      client = MDnsClient(
        rawDatagramSocketFactory: Platform.isWindows
            ? (
                dynamic host,
                int port, {
                bool reuseAddress = true,
                bool reusePort = true,
                int ttl = 255,
              }) => RawDatagramSocket.bind(
                host,
                port,
                reuseAddress: reuseAddress,
                reusePort: false,
                ttl: ttl,
              )
            : RawDatagramSocket.bind,
      );
      await client.start(interfacesFactory: _selectMulticastInterfaces);
      started = true;
      onClientCreated(client);
      if (isCancelled()) return;

      const String serviceType = '_smarthome._tcp.local';
      final probeFutures = <Future<void>>[];
      await for (final PtrResourceRecord ptr
          in client.lookup<PtrResourceRecord>(
            ResourceRecordQuery.serverPointer(serviceType),
            timeout: const Duration(seconds: 3),
          )) {
        if (isCancelled()) break;
        probeFutures.add(() async {
          try {
            await for (final SrvResourceRecord srv
                in client!.lookup<SrvResourceRecord>(
                  ResourceRecordQuery.service(ptr.domainName),
                  timeout: const Duration(milliseconds: 1200),
                )) {
              if (isCancelled()) break;
              await for (final IPAddressResourceRecord ipRecord
                  in client.lookup<IPAddressResourceRecord>(
                    ResourceRecordQuery.addressIPv4(srv.target),
                    timeout: const Duration(milliseconds: 1200),
                  )) {
                if (isCancelled()) break;
                final hostIp = ipRecord.address.address;
                final dev = await _probeHost(hostIp, cancelToken);
                if (dev != null && !isCancelled()) {
                  onFound(dev);
                }
              }
            }
          } catch (_) {}
        }());
      }
      if (probeFutures.isNotEmpty) {
        await Future.wait(probeFutures);
      }
    } catch (_) {
    } finally {
      if (client != null) {
        if (started) {
          try {
            client.stop();
          } catch (_) {}
        }
        onClientClosed(client);
      }
    }
  }

  /// 2. Fast Multi-Interface Subnet Probe Scan (/24)
  ///
  /// Enumerates all active private LAN adapters (Ethernet & Wi-Fi on Windows,
  /// Wi-Fi on mobile) and uses a bounded worker pool of fast TCP:80 checks
  /// before issuing `/api/discovery`, finishing an entire `/24` in ~2-3s.
  Future<void> _scanSubnet(
    void Function(SmartDevice) onFound,
    bool Function() isCancelled,
    CancelToken cancelToken,
  ) async {
    try {
      final targetInfo = await _discoverLocalSubnets();
      if (targetInfo.subnets.isEmpty || isCancelled()) return;

      final candidates = <String>[];
      for (int host = 1; host <= 254; host++) {
        for (final subnet in targetInfo.subnets) {
          final ip = '$subnet.$host';
          if (!targetInfo.localIps.contains(ip)) {
            candidates.add(ip);
          }
        }
      }
      if (candidates.isEmpty || isCancelled()) return;

      int cursor = 0;
      const int workerCount = 80;
      await Future.wait(
        List.generate(workerCount, (_) async {
          while (!isCancelled() && cursor < candidates.length) {
            final targetIp = candidates[cursor++];
            if (!await _isPort80Open(targetIp, isCancelled)) {
              continue;
            }
            if (isCancelled()) return;
            final dev = await _probeHost(targetIp, cancelToken);
            if (dev != null && !isCancelled()) {
              onFound(dev);
            }
          }
        }),
      );
    } catch (_) {}
  }
}
