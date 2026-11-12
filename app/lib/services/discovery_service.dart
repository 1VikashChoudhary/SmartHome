import 'dart:async';
import 'package:multicast_dns/multicast_dns.dart';
import 'package:network_info_plus/network_info_plus.dart';
import '../core/models/smart_device.dart';
import '../core/network/api_client.dart';

class DiscoveryService {
  final ApiClient _api = ApiClient();
  final NetworkInfo _netInfo = NetworkInfo();

  /// Discover all devices via mDNS and parallel subnet ping
  Future<List<SmartDevice>> discoverAll({void Function(SmartDevice device)? onDeviceFound}) async {
    final Map<String, SmartDevice> foundMap = {};
    bool isCancelled = false;

    void addDevice(SmartDevice dev) {
      final key = (dev.mac.isNotEmpty && dev.mac != '00:00:00:00:00:00')
          ? dev.mac
          : (dev.id.isNotEmpty ? dev.id : dev.ip);
      if (!foundMap.containsKey(key)) {
        foundMap[key] = dev;
        onDeviceFound?.call(dev);
      }
    }

    // Run both mDNS and Subnet scan concurrently with a 5-second timeout
    await Future.wait([
      _scanMDNS(addDevice, () => isCancelled),
      _scanSubnet(addDevice, () => isCancelled),
    ]).timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        isCancelled = true;
        return [];
      },
    );

    return foundMap.values.toList();
  }

  /// 1. Pure Dart mDNS Zero-Conf Scan (_smarthome._tcp)
  Future<void> _scanMDNS(
    void Function(SmartDevice) onFound,
    bool Function() isCancelled,
  ) async {
    MDnsClient? client;
    try {
      client = MDnsClient();
      await client.start();

      const String serviceType = '_smarthome._tcp.local';
      await for (final PtrResourceRecord ptr in client.lookup<PtrResourceRecord>(
        ResourceRecordQuery.serverPointer(serviceType),
      )) {
        if (isCancelled()) break;
        await for (final SrvResourceRecord srv in client.lookup<SrvResourceRecord>(
          ResourceRecordQuery.service(ptr.domainName),
        )) {
          if (isCancelled()) break;
          await for (final IPAddressResourceRecord ipRecord in client.lookup<IPAddressResourceRecord>(
            ResourceRecordQuery.addressIPv4(srv.target),
          )) {
            if (isCancelled()) break;
            final hostIp = ipRecord.address.address;
            final dev = await _api.probeDiscovery(hostIp);
            if (dev != null && !isCancelled()) {
              onFound(dev);
            }
          }
        }
      }
    } catch (_) {
    } finally {
      client?.stop();
    }
  }

  /// 2. Fast Parallel Subnet Probe Scan (/24)
  Future<void> _scanSubnet(
    void Function(SmartDevice) onFound,
    bool Function() isCancelled,
  ) async {
    try {
      final wifiIp = await _netInfo.getWifiIP();
      if (wifiIp == null || !wifiIp.contains('.')) return;

      final parts = wifiIp.split('.');
      if (parts.length != 4) return;
      final subnet = '${parts[0]}.${parts[1]}.${parts[2]}';

      // Scan in parallel batches of 32 IPs
      const batchSize = 32;
      for (int i = 1; i <= 254; i += batchSize) {
        if (isCancelled()) break;
        final futures = <Future>[];
        for (int j = i; j < i + batchSize && j <= 254; j++) {
          final targetIp = '$subnet.$j';
          futures.add(_api.probeDiscovery(targetIp).then((dev) {
            if (dev != null && !isCancelled()) onFound(dev);
          }));
        }
        await Future.wait(futures);
      }
    } catch (_) {}
  }
}
