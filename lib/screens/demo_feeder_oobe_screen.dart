/// Demo Feeder OOBE Screen
/// Simulates the Ornimetrics OS feeder setup process for testing

import 'dart:async';
import 'dart:math' as math;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/feeder_models.dart';

class DemoFeederOobeScreen extends StatefulWidget {
  const DemoFeederOobeScreen({super.key});

  @override
  State<DemoFeederOobeScreen> createState() => _DemoFeederOobeScreenState();
}

class _DemoFeederOobeScreenState extends State<DemoFeederOobeScreen>
    with TickerProviderStateMixin {
  // Current step in the OOBE process
  SetupStep _currentStep = SetupStep.scanning;

  // Animation controllers
  late AnimationController _scanAnimController;
  late AnimationController _pulseAnimController;
  late AnimationController _progressAnimController;
  late AnimationController _successAnimController;

  // State
  bool _deviceFound = false;
  String _statusMessage = '';
  double _progress = 0.0;
  List<_SimulatedDevice> _discoveredDevices = [];
  _SimulatedDevice? _selectedDevice;

  // Demo WiFi config
  final _ssidController = TextEditingController(text: 'Home_Network_5G');
  final _passwordController = TextEditingController(text: '********');
  bool _showPassword = false;

  @override
  void initState() {
    super.initState();

    _scanAnimController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    _pulseAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _progressAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _successAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _startSimulation();
  }

  void _startSimulation() async {
    setState(() {
      _currentStep = SetupStep.scanning;
      _statusMessage = 'Looking for nearby Ornimetrics feeders...';
    });

    // Simulate scanning delay
    await Future.delayed(const Duration(seconds: 2));

    if (!mounted) return;

    // Add devices one by one with animation
    final devices = [
      _SimulatedDevice(
        id: 'demo-feeder-001',
        name: 'Ornimetrics-Demo-01',
        rssi: -45,
        hasHailo: true,
        hasDepthCamera: true,
      ),
      _SimulatedDevice(
        id: 'demo-feeder-002',
        name: 'Ornimetrics-Lite-02',
        rssi: -68,
        hasHailo: false,
        hasDepthCamera: false,
      ),
    ];

    for (final device in devices) {
      await Future.delayed(const Duration(milliseconds: 800));
      if (!mounted) return;
      HapticFeedback.lightImpact();
      setState(() {
        _discoveredDevices.add(device);
        _deviceFound = true;
      });
    }
  }

  Future<void> _selectDevice(_SimulatedDevice device) async {
    HapticFeedback.selectionClick();
    setState(() {
      _selectedDevice = device;
      _currentStep = SetupStep.connecting;
      _statusMessage = 'Connecting to ${device.name}...';
    });

    // Simulate connection
    await _simulateProgress(1.5);

    if (!mounted) return;

    setState(() {
      _currentStep = SetupStep.pairing;
      _statusMessage = 'Securing connection...';
      _progress = 0;
    });

    // Simulate pairing
    await _simulateProgress(1.2);

    if (!mounted) return;

    setState(() {
      _currentStep = SetupStep.linkingAccount;
      _statusMessage = 'Linking to your account...';
      _progress = 0;
    });

    // Simulate account linking
    await _simulateProgress(1.0);

    if (!mounted) return;

    // Move to WiFi config
    setState(() {
      _currentStep = SetupStep.configuringWifi;
      _statusMessage = 'Configure your WiFi network';
      _progress = 0;
    });
  }

  Future<void> _simulateProgress(double durationSeconds) async {
    final steps = 20;
    final stepDuration = Duration(milliseconds: (durationSeconds * 1000 / steps).round());

    for (int i = 0; i <= steps; i++) {
      if (!mounted) return;
      await Future.delayed(stepDuration);
      setState(() {
        _progress = i / steps;
      });
    }
  }

  Future<void> _configureWifi() async {
    HapticFeedback.selectionClick();

    setState(() {
      _statusMessage = 'Configuring WiFi...';
    });

    await _simulateProgress(2.0);

    if (!mounted) return;

    setState(() {
      _currentStep = SetupStep.verifying;
      _statusMessage = 'Verifying connection...';
      _progress = 0;
    });

    await _simulateProgress(1.5);

    if (!mounted) return;

    // Success!
    setState(() {
      _currentStep = SetupStep.complete;
      _statusMessage = 'Setup complete!';
    });

    _successAnimController.forward();
    HapticFeedback.heavyImpact();
  }

  Future<void> _finishSetup() async {
    HapticFeedback.selectionClick();

    // Create demo paired feeder
    final demoFeeder = PairedFeeder(
      deviceId: _selectedDevice?.id ?? 'demo-feeder-001',
      deviceName: _selectedDevice?.name ?? 'Demo Ornimetrics',
      feederName: 'Demo Backyard Feeder',
      staticIp: '192.168.1.200',
      version: '1.0.0',
      pairedAt: DateTime.now(),
      userId: FirebaseAuth.instance.currentUser?.uid ?? 'demo-user',
    );

    Navigator.of(context).pop(demoFeeder);
  }

  @override
  void dispose() {
    _scanAnimController.dispose();
    _pulseAnimController.dispose();
    _progressAnimController.dispose();
    _successAnimController.dispose();
    _ssidController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Demo Feeder Setup'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // Progress steps
          _buildProgressSteps(colorScheme),

          // Main content
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0.05, 0),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                );
              },
              child: _buildStepContent(colorScheme),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressSteps(ColorScheme colorScheme) {
    final steps = [
      (SetupStep.scanning, Icons.bluetooth_searching),
      (SetupStep.connecting, Icons.link),
      (SetupStep.pairing, Icons.security),
      (SetupStep.linkingAccount, Icons.person),
      (SetupStep.configuringWifi, Icons.wifi),
      (SetupStep.verifying, Icons.check_circle_outline),
      (SetupStep.complete, Icons.celebration),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: Row(
        children: steps.asMap().entries.map((entry) {
          final index = entry.key;
          final step = entry.value.$1;
          final icon = entry.value.$2;
          final isActive = _currentStep.stepIndex >= step.stepIndex;
          final isCurrent = _currentStep == step;

          return Expanded(
            child: Row(
              children: [
                // Step circle
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: isCurrent ? 36 : 28,
                  height: isCurrent ? 36 : 28,
                  decoration: BoxDecoration(
                    color: isActive
                        ? colorScheme.primary
                        : colorScheme.surfaceContainerHighest,
                    shape: BoxShape.circle,
                    boxShadow: isCurrent
                        ? [
                            BoxShadow(
                              color: colorScheme.primary.withOpacity(0.4),
                              blurRadius: 8,
                              spreadRadius: 2,
                            ),
                          ]
                        : null,
                  ),
                  child: Icon(
                    icon,
                    size: isCurrent ? 18 : 14,
                    color: isActive
                        ? colorScheme.onPrimary
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
                // Connector line
                if (index < steps.length - 1)
                  Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      height: 2,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: _currentStep.stepIndex > step.stepIndex
                            ? colorScheme.primary
                            : colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildStepContent(ColorScheme colorScheme) {
    switch (_currentStep) {
      case SetupStep.scanning:
        return _buildScanningContent(colorScheme);
      case SetupStep.connecting:
      case SetupStep.pairing:
      case SetupStep.linkingAccount:
        return _buildProgressContent(colorScheme);
      case SetupStep.configuringWifi:
        return _buildWifiConfigContent(colorScheme);
      case SetupStep.verifying:
        return _buildProgressContent(colorScheme);
      case SetupStep.complete:
        return _buildCompleteContent(colorScheme);
    }
  }

  Widget _buildScanningContent(ColorScheme colorScheme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        key: const ValueKey('scanning'),
        children: [
          // Animated scanning indicator
          SizedBox(
            height: 180,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Scanning waves
                ...List.generate(3, (i) {
                  return AnimatedBuilder(
                    animation: _scanAnimController,
                    builder: (context, child) {
                      final progress = ((_scanAnimController.value + i * 0.33) % 1.0);
                      return Opacity(
                        opacity: 1 - progress,
                        child: Container(
                          width: 80 + (progress * 100),
                          height: 80 + (progress * 100),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: colorScheme.primary.withOpacity(0.5),
                              width: 2,
                            ),
                          ),
                        ),
                      );
                    },
                  );
                }),
                // Center icon
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.bluetooth_searching,
                    size: 40,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          Text(
            _currentStep.title,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _statusMessage,
            style: TextStyle(
              fontSize: 14,
              color: colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),

          // Discovered devices
          if (_discoveredDevices.isNotEmpty) ...[
            Text(
              'Nearby Feeders',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            ...List.generate(_discoveredDevices.length, (index) {
              return TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 400),
                builder: (context, value, child) {
                  return Opacity(
                    opacity: value,
                    child: Transform.translate(
                      offset: Offset(20 * (1 - value), 0),
                      child: child,
                    ),
                  );
                },
                child: _buildDeviceCard(
                  _discoveredDevices[index],
                  colorScheme,
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildDeviceCard(_SimulatedDevice device, ColorScheme colorScheme) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _selectDevice(device),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.rss_feed,
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        // Hardware badges
                        if (device.hasHailo)
                          _buildBadge('Hailo AI', Colors.purple, colorScheme),
                        if (device.hasHailo && device.hasDepthCamera)
                          const SizedBox(width: 6),
                        if (device.hasDepthCamera)
                          _buildBadge('3D ToF', Colors.blue, colorScheme),
                      ],
                    ),
                  ],
                ),
              ),
              // Signal strength
              Column(
                children: [
                  Icon(
                    device.rssi > -60
                        ? Icons.signal_wifi_4_bar
                        : Icons.signal_wifi_4_bar_outlined,
                    color: device.rssi > -60 ? Colors.green : Colors.orange,
                    size: 20,
                  ),
                  Text(
                    '${device.rssi} dBm',
                    style: TextStyle(
                      fontSize: 10,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBadge(String label, Color color, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Widget _buildProgressContent(ColorScheme colorScheme) {
    return Padding(
      key: ValueKey(_currentStep),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Animated progress circle
          SizedBox(
            width: 160,
            height: 160,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Background circle
                SizedBox(
                  width: 160,
                  height: 160,
                  child: CircularProgressIndicator(
                    value: 1,
                    strokeWidth: 8,
                    backgroundColor: colorScheme.surfaceContainerHighest,
                    color: colorScheme.surfaceContainerHighest,
                  ),
                ),
                // Progress circle
                SizedBox(
                  width: 160,
                  height: 160,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: _progress),
                    duration: const Duration(milliseconds: 200),
                    builder: (context, value, _) {
                      return CircularProgressIndicator(
                        value: value,
                        strokeWidth: 8,
                        strokeCap: StrokeCap.round,
                        backgroundColor: Colors.transparent,
                        color: colorScheme.primary,
                      );
                    },
                  ),
                ),
                // Center content
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _getStepIcon(_currentStep),
                      size: 40,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${(_progress * 100).round()}%',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),

          Text(
            _currentStep.title,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _statusMessage,
            style: TextStyle(
              fontSize: 14,
              color: colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),

          if (_selectedDevice != null) ...[
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.rss_feed, color: colorScheme.primary),
                  const SizedBox(width: 12),
                  Text(
                    _selectedDevice!.name,
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildWifiConfigContent(ColorScheme colorScheme) {
    return SingleChildScrollView(
      key: const ValueKey('wifi'),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.wifi,
                  color: colorScheme.onPrimaryContainer,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'WiFi Setup',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      'Connect your feeder to your network',
                      style: TextStyle(
                        fontSize: 14,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),

          // SSID Field
          TextField(
            controller: _ssidController,
            decoration: InputDecoration(
              labelText: 'Network Name (SSID)',
              prefixIcon: const Icon(Icons.wifi),
              filled: true,
              fillColor: colorScheme.surfaceContainerHighest,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Password Field
          TextField(
            controller: _passwordController,
            obscureText: !_showPassword,
            decoration: InputDecoration(
              labelText: 'Password',
              prefixIcon: const Icon(Icons.lock),
              suffixIcon: IconButton(
                icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _showPassword = !_showPassword),
              ),
              filled: true,
              fillColor: colorScheme.surfaceContainerHighest,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Device info
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withOpacity(0.3),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colorScheme.primary.withOpacity(0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline, size: 18, color: colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      'Device Info',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildInfoRow('Device', _selectedDevice?.name ?? 'Demo', colorScheme),
                _buildInfoRow('Hardware', _selectedDevice?.hasHailo == true ? 'Hailo AI + 3D ToF' : 'Standard', colorScheme),
                _buildInfoRow('Static IP', '192.168.1.200', colorScheme),
              ],
            ),
          ),
          const SizedBox(height: 32),

          // Connect button
          SizedBox(
            width: double.infinity,
            height: 56,
            child: FilledButton.icon(
              onPressed: _configureWifi,
              icon: const Icon(Icons.check),
              label: const Text('Configure WiFi'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w500,
              color: colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompleteContent(ColorScheme colorScheme) {
    return Padding(
      key: const ValueKey('complete'),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Success animation
          ScaleTransition(
            scale: CurvedAnimation(
              parent: _successAnimController,
              curve: Curves.elasticOut,
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Animated rings
                ...List.generate(3, (i) {
                  return AnimatedBuilder(
                    animation: _pulseAnimController,
                    builder: (context, _) {
                      return Container(
                        width: 120 + (i * 30) + (_pulseAnimController.value * 10),
                        height: 120 + (i * 30) + (_pulseAnimController.value * 10),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.green.withOpacity(0.2 - (i * 0.05)),
                            width: 2,
                          ),
                        ),
                      );
                    },
                  );
                }),
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.green.shade400,
                        Colors.green.shade600,
                      ],
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.green.withOpacity(0.4),
                        blurRadius: 20,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.check,
                    size: 50,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),

          Text(
            'Setup Complete!',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Your demo feeder is ready to use.\nExplore all the features in the Feeder tab.',
            style: TextStyle(
              fontSize: 16,
              color: colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),

          // Hardware summary
          if (_selectedDevice != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(Icons.rss_feed, color: colorScheme.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _selectedDevice!.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      if (_selectedDevice!.hasHailo)
                        Expanded(
                          child: _buildFeatureSummary(
                            Icons.auto_awesome,
                            'Hailo AI',
                            Colors.purple,
                          ),
                        ),
                      if (_selectedDevice!.hasHailo && _selectedDevice!.hasDepthCamera)
                        const SizedBox(width: 12),
                      if (_selectedDevice!.hasDepthCamera)
                        Expanded(
                          child: _buildFeatureSummary(
                            Icons.view_in_ar,
                            '3D ToF',
                            Colors.blue,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          const SizedBox(height: 32),

          SizedBox(
            width: double.infinity,
            height: 56,
            child: FilledButton.icon(
              onPressed: _finishSetup,
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Go to Feeder Tab'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureSummary(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  IconData _getStepIcon(SetupStep step) {
    switch (step) {
      case SetupStep.scanning:
        return Icons.bluetooth_searching;
      case SetupStep.connecting:
        return Icons.link;
      case SetupStep.pairing:
        return Icons.security;
      case SetupStep.linkingAccount:
        return Icons.person;
      case SetupStep.configuringWifi:
        return Icons.wifi;
      case SetupStep.verifying:
        return Icons.check_circle_outline;
      case SetupStep.complete:
        return Icons.celebration;
    }
  }
}

class _SimulatedDevice {
  final String id;
  final String name;
  final int rssi;
  final bool hasHailo;
  final bool hasDepthCamera;

  const _SimulatedDevice({
    required this.id,
    required this.name,
    required this.rssi,
    required this.hasHailo,
    required this.hasDepthCamera,
  });
}
