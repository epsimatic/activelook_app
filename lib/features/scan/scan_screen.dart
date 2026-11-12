import 'dart:async';

import 'package:flutter/material.dart';

import '../../ble/ble_glasses_transport.dart';
import '../../ble/glasses_scanner.dart';
import '../../ble/glasses_transport.dart';
import '../../ble/mock_glasses.dart';
import '../../models/discovered_glasses.dart';
import '../glasses/glasses_controller.dart';
import '../glasses/glasses_screen.dart';

/// Scans for ActiveLook glasses and opens the control screen.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key, this.scanner, this.transportFactory});

  /// Injectable for tests; defaults to the real BLE scanner.
  final GlassesScanner? scanner;

  /// Injectable for tests; defaults to the real BLE transport.
  final GlassesTransport Function()? transportFactory;

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  late final GlassesScanner _scanner = widget.scanner ?? BleGlassesScanner();
  final Map<String, DiscoveredGlasses> _devices = {};
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  bool _scanning = false;
  bool _showAllDevices = false;
  String? _error;
  String? _connectingId;

  @override
  void initState() {
    super.initState();
    _subscriptions.addAll([
      _scanner.scanning.listen((scanning) {
        if (!mounted) return;
        setState(() => _scanning = scanning);
      }),
      _scanner.results.listen((device) {
        if (!mounted) return;
        setState(() => _devices[device.id] = device);
      }),
      _scanner.errors.listen((error) {
        if (!mounted) return;
        setState(() => _error = error);
      }),
    ]);
    WidgetsBinding.instance.addPostFrameCallback((_) => _startScan());
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _scanner.dispose();
    super.dispose();
  }

  Future<void> _startScan() async {
    setState(() => _error = null);
    await _scanner.start();
  }

  Future<void> _stopScan() => _scanner.stop();

  List<DiscoveredGlasses> get _visibleDevices {
    final devices = _devices.values
        .where((device) => _showAllDevices || device.isActiveLook)
        .toList();
    devices.sort((a, b) {
      if (a.isActiveLook != b.isActiveLook) return a.isActiveLook ? -1 : 1;
      return b.rssi.compareTo(a.rssi);
    });
    return devices;
  }

  Future<void> _connect(DiscoveredGlasses device) async {
    await _stopScan();
    if (!mounted) return;
    setState(() {
      _connectingId = device.id;
      _error = null;
    });

    final controller = GlassesController(
      transport: widget.transportFactory?.call() ?? BleGlassesTransport(),
    );
    await controller.connect(device);
    if (!mounted) {
      controller.dispose();
      return;
    }
    setState(() => _connectingId = null);

    if (!controller.connected) {
      controller.dispose();
      await _startScan();
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GlassesScreen(controller: controller),
      ),
    );
    if (mounted) await _startScan();
  }

  Future<void> _openSimulator() async {
    await _stopScan();
    if (!mounted) return;

    final controller = GlassesController(transport: MockGlassesTransport());
    await controller.connect(
      const DiscoveredGlasses(
        id: 'SIMULATED-0001',
        name: 'A.Look DEMO01',
        rssi: -42,
        isActiveLook: true,
      ),
    );
    if (!mounted) {
      controller.dispose();
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GlassesScreen(controller: controller),
      ),
    );
    if (mounted) await _startScan();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final devices = _visibleDevices;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Демо ActiveLook'),
        actions: [
          IconButton(
            tooltip: _scanning ? 'Остановить поиск' : 'Искать снова',
            onPressed: _scanning ? _stopScan : _startScan,
            icon: Icon(_scanning ? Icons.stop_circle_outlined : Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _startScan,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _HeaderCard(scanning: _scanning),
            if (_error != null) ...[
              const SizedBox(height: 12),
              _ErrorCard(message: _error!),
            ],
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Показывать все Bluetooth-устройства'),
              subtitle: const Text('Помогает, если очки не находятся'),
              value: _showAllDevices,
              onChanged: (value) => setState(() => _showAllDevices = value),
            ),
            const SizedBox(height: 8),
            if (devices.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Column(
                  children: [
                    Icon(
                      Icons.bluetooth_searching,
                      size: 48,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _scanning
                          ? 'Ищем очки ActiveLook…'
                          : 'Очки ActiveLook не найдены',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Включите очки и убедитесь, что они не подключены '
                      'к другому телефону или часам.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            for (final device in devices)
              _DeviceTile(
                device: device,
                connecting: _connectingId == device.id,
                onTap: _connectingId == null ? () => _connect(device) : null,
              ),
            const SizedBox(height: 24),
            Card(
              child: ListTile(
                leading: const Icon(Icons.science_outlined),
                title: const Text('Запустить демо без очков'),
                subtitle: const Text(
                  'Имитация подключения, Bluetooth не нужен',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: _openSimulator,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.scanning});

  final bool scanning;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            SizedBox(
              width: 42,
              height: 42,
              child: scanning
                  ? const CircularProgressIndicator(strokeWidth: 3)
                  : Icon(
                      Icons.visibility_outlined,
                      color: theme.colorScheme.primary,
                    ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Подключение к очкам',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    scanning ? 'Ищем рекламные пакеты ActiveLook…' : 'Поиск остановлен. Потяните вниз или нажмите «Обновить».',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      color: colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, color: colorScheme.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: colorScheme.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({
    required this.device,
    required this.connecting,
    required this.onTap,
  });

  final DiscoveredGlasses device;
  final bool connecting;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: ListTile(
        onTap: onTap,
        leading: Icon(
          device.isActiveLook ? Icons.visibility : Icons.bluetooth,
          color: device.isActiveLook ? theme.colorScheme.primary : null,
        ),
        title: Text(device.displayName),
        subtitle: Text(
          device.isActiveLook
              ? 'Очки ActiveLook'
              : 'Bluetooth-устройство — ${device.id}',
        ),
        trailing: connecting
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text('${device.rssi} dBm', style: theme.textTheme.labelSmall),
      ),
    );
  }
}
