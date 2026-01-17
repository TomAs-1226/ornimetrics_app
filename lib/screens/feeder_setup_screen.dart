/// Device Setup/Pairing screen for Ornimetrics OS
/// Handles Bluetooth discovery, pairing, WiFi configuration, and account linking

import 'dart:async';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/feeder_models.dart';
import '../services/feeder_bluetooth_service.dart';
import '../services/feeder_api_service.dart';

class FeederSetupScreen extends StatefulWidget {
  final VoidCallback? onSetupComplete;

  const FeederSetupScreen({super.key, this.onSetupComplete});

  @override
  State<FeederSetupScreen> createState() => _FeederSetupScreenState();
}

class _FeederSetupScreenState extends State<FeederSetupScreen>
    with TickerProviderStateMixin {
  final _bluetoothService = FeederBluetoothService.instance;
  final _formKey = GlobalKey<FormState>();

  // Controllers
  final _ssidController = TextEditingController();
  final _passwordController = TextEditingController();
  final _feederNameController = TextEditingController(text: 'My Feeder');

  // Animation controllers
  late AnimationController _pulseController;
  late AnimationController _progressController;
  late Animation<double> _pulseAnimation;

  // State
  bool _isBluetoothAvailable = false;
  bool _showPassword = false;
  bool _isProcessing = false;
  OrnimetricsDevice? _selectedDevice;
  String? _error;
  SetupStep _currentStep = SetupStep.scanning;

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _checkBluetooth();
  }

  void _initAnimations() {
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  Future<void> _checkBluetooth() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      setState(() {
        _error = 'Bluetooth is only supported on mobile devices';
        _isBluetoothAvailable = false;
      });
      return;
    }

    final available = await _bluetoothService.isBluetoothAvailable();
    setState(() => _isBluetoothAvailable = available);

    if (!available) {
      final granted = await _bluetoothService.requestPermissions();
      setState(() => _isBluetoothAvailable = granted);
    }

    if (_isBluetoothAvailable) {
      _startScanning();
    }
  }

  Future<void> _startScanning() async {
    setState(() {
      _currentStep = SetupStep.scanning;
      _error = null;
      _selectedDevice = null;
    });
    await _bluetoothService.startScan();
  }

  Future<void> _selectDevice(OrnimetricsDevice device) async {
    HapticFeedback.selectionClick();
    setState(() {
      _selectedDevice = device;
      _currentStep = SetupStep.connecting;
      _isProcessing = true;
      _error = null;
    });

    final connected = await _bluetoothService.connectToDevice(device);
    if (!connected) {
      setState(() {
        _error = _bluetoothService.errorMessage.value ?? 'Connection failed';
        _isProcessing = false;
        _currentStep = SetupStep.scanning;
      });
      return;
    }

    // Pair with device
    setState(() => _currentStep = SetupStep.pairing);
    final session = await _bluetoothService.pair(
      appId: 'ornimetrics-flutter-app',
      deviceModel: Platform.isIOS ? 'iOS Device' : 'Android Device',
      appVersion: '2.1.0',
    );

    if (session == null) {
      setState(() {
        _error = _bluetoothService.errorMessage.value ?? 'Pairing failed';
        _isProcessing = false;
      });
      return;
    }

    setState(() {
      _isProcessing = false;
      _currentStep = SetupStep.configuringWifi;
    });
  }

  Future<void> _configureWifi() async {
    if (!_formKey.currentState!.validate()) return;

    HapticFeedback.lightImpact();
    setState(() {
      _isProcessing = true;
      _error = null;
    });

    // Link account first
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      setState(() => _currentStep = SetupStep.linkingAccount);
      final linked = await _bluetoothService.linkAccount(
        userId: user.uid,
        accountEmail: user.email ?? '',
        accountToken: await user.getIdToken() ?? '',
        feederName: _feederNameController.text,
      );

      if (!linked) {
        setState(() {
          _error = _bluetoothService.errorMessage.value ?? 'Account linking failed';
          _isProcessing = false;
        });
        return;
      }
    }

    // Configure WiFi
    setState(() => _currentStep = SetupStep.configuringWifi);
    final result = await _bluetoothService.configureWifi(
      ssid: _ssidController.text,
      password: _passwordController.text,
    );

    if (result == null || !result.success) {
      setState(() {
        _error = result?.errorMessage ?? 'WiFi configuration failed';
        _isProcessing = false;
      });
      return;
    }

    // Complete setup
    setState(() => _currentStep = SetupStep.verifying);
    final feeder = await _bluetoothService.completeSetup(
      userId: user?.uid ?? 'anonymous',
      feederName: _feederNameController.text,
    );

    if (feeder == null) {
      setState(() {
        _error = _bluetoothService.errorMessage.value ?? 'Setup verification failed';
        _isProcessing = false;
      });
      return;
    }

    // Configure API service
    FeederApiService.instance.setFromPairedFeeder(feeder);

    // Disconnect Bluetooth
    await _bluetoothService.disconnect();

    setState(() {
      _isProcessing = false;
      _currentStep = SetupStep.complete;
    });

    // Delay then complete
    await Future.delayed(const Duration(seconds: 2));
    widget.onSetupComplete?.call();
    if (mounted) {
      Navigator.of(context).pop(feeder);
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _progressController.dispose();
    _ssidController.dispose();
    _passwordController.dispose();
    _feederNameController.dispose();
    _bluetoothService.stopScan();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Feeder'),
        centerTitle: true,
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Progress indicator
            _buildProgressIndicator(colorScheme),

            // Content
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: _buildCurrentStep(theme, colorScheme),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressIndicator(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        children: [
          Row(
            children: List.generate(7, (index) {
              final isActive = index <= _currentStep.stepIndex;
              final isCurrent = index == _currentStep.stepIndex;
              return Expanded(
                child: Container(
                  height: 4,
                  margin: EdgeInsets.only(right: index < 6 ? 4 : 0),
                  decoration: BoxDecoration(
                    color: isActive
                        ? (isCurrent ? colorScheme.primary : colorScheme.primary.withOpacity(0.5))
                        : colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 12),
          Text(
            _currentStep.title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _currentStep.description,
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentStep(ThemeData theme, ColorScheme colorScheme) {
    if (!_isBluetoothAvailable && _currentStep == SetupStep.scanning) {
      return _buildBluetoothUnavailable(colorScheme);
    }

    switch (_currentStep) {
      case SetupStep.scanning:
      case SetupStep.connecting:
      case SetupStep.pairing:
        return _buildScanningStep(theme, colorScheme);
      case SetupStep.linkingAccount:
      case SetupStep.configuringWifi:
        return _buildWifiStep(theme, colorScheme);
      case SetupStep.verifying:
        return _buildVerifyingStep(colorScheme);
      case SetupStep.complete:
        return _buildCompleteStep(colorScheme);
    }
  }

  Widget _buildBluetoothUnavailable(ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.bluetooth_disabled,
              size: 80,
              color: colorScheme.error,
            ),
            const SizedBox(height: 24),
            Text(
              'Bluetooth Required',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _error ?? 'Please enable Bluetooth to set up your feeder.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: _checkBluetooth,
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScanningStep(ThemeData theme, ColorScheme colorScheme) {
    return Column(
      children: [
        // Scanning animation
        if (_currentStep == SetupStep.scanning)
          Padding(
            padding: const EdgeInsets.all(32),
            child: ScaleTransition(
              scale: _pulseAnimation,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colorScheme.primaryContainer,
                  boxShadow: [
                    BoxShadow(
                      color: colorScheme.primary.withOpacity(0.3),
                      blurRadius: 30,
                      spreadRadius: 10,
                    ),
                  ],
                ),
                child: Icon(
                  Icons.bluetooth_searching,
                  size: 48,
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
            ),
          ),

        // Error message
        if (_error != null)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline, color: colorScheme.onErrorContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _error!,
                    style: TextStyle(color: colorScheme.onErrorContainer),
                  ),
                ),
              ],
            ),
          ),

        // Discovered devices list
        Expanded(
          child: ValueListenableBuilder<List<OrnimetricsDevice>>(
            valueListenable: _bluetoothService.discoveredDevices,
            builder: (context, devices, _) {
              if (devices.isEmpty && _bluetoothService.isScanning.value) {
                return const Center(
                  child: Text('Searching for nearby feeders...'),
                );
              }

              if (devices.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.device_unknown,
                        size: 64,
                        color: colorScheme.outline,
                      ),
                      const SizedBox(height: 16),
                      const Text('No feeders found'),
                      const SizedBox(height: 24),
                      OutlinedButton.icon(
                        onPressed: _isProcessing ? null : _startScanning,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Scan Again'),
                      ),
                    ],
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: devices.length,
                itemBuilder: (context, index) {
                  final device = devices[index];
                  final isSelected = _selectedDevice?.id == device.id;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    color: isSelected ? colorScheme.primaryContainer : null,
                    child: ListTile(
                      leading: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? colorScheme.primary
                              : colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.rss_feed,
                          color: isSelected
                              ? colorScheme.onPrimary
                              : colorScheme.onSurfaceVariant,
                        ),
                      ),
                      title: Text(
                        device.displayName,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text('Signal: ${device.rssi} dBm'),
                      trailing: isSelected && _isProcessing
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              Icons.chevron_right,
                              color: colorScheme.onSurfaceVariant,
                            ),
                      onTap: _isProcessing ? null : () => _selectDevice(device),
                    ),
                  );
                },
              );
            },
          ),
        ),

        // Scan button
        Padding(
          padding: const EdgeInsets.all(24),
          child: ValueListenableBuilder<bool>(
            valueListenable: _bluetoothService.isScanning,
            builder: (context, isScanning, _) {
              return SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _isProcessing
                      ? null
                      : (isScanning ? _bluetoothService.stopScan : _startScanning),
                  icon: Icon(isScanning ? Icons.stop : Icons.refresh),
                  label: Text(isScanning ? 'Stop Scanning' : 'Scan Again'),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildWifiStep(ThemeData theme, ColorScheme colorScheme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Device info card
            if (_selectedDevice != null)
              Card(
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
                          Icons.check_circle,
                          color: colorScheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _selectedDevice!.displayName,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            Text(
                              'Connected via Bluetooth',
                              style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 24),

            // Feeder name
            TextFormField(
              controller: _feederNameController,
              decoration: const InputDecoration(
                labelText: 'Feeder Name',
                hintText: 'e.g., Backyard Feeder',
                prefixIcon: Icon(Icons.edit),
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter a name for your feeder';
                }
                return null;
              },
            ),

            const SizedBox(height: 16),

            // WiFi SSID
            TextFormField(
              controller: _ssidController,
              decoration: const InputDecoration(
                labelText: 'WiFi Network Name (SSID)',
                hintText: 'Enter your WiFi network name',
                prefixIcon: Icon(Icons.wifi),
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter your WiFi network name';
                }
                return null;
              },
            ),

            const SizedBox(height: 16),

            // WiFi Password
            TextFormField(
              controller: _passwordController,
              obscureText: !_showPassword,
              decoration: InputDecoration(
                labelText: 'WiFi Password',
                hintText: 'Enter your WiFi password',
                prefixIcon: const Icon(Icons.lock),
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _showPassword = !_showPassword),
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter your WiFi password';
                }
                return null;
              },
            ),

            const SizedBox(height: 24),

            // Error message
            if (_error != null)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: colorScheme.onErrorContainer),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _error!,
                        style: TextStyle(color: colorScheme.onErrorContainer),
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 24),

            // Submit button
            FilledButton(
              onPressed: _isProcessing ? null : _configureWifi,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: _isProcessing
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Complete Setup'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVerifyingStep(ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 100,
            height: 100,
            child: CircularProgressIndicator(
              strokeWidth: 6,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(height: 32),
          Text(
            'Verifying Connection...',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'This may take a moment',
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompleteStep(ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 600),
            curve: Curves.elasticOut,
            builder: (context, value, child) {
              return Transform.scale(
                scale: value,
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colorScheme.primaryContainer,
                  ),
                  child: Icon(
                    Icons.check_circle,
                    size: 60,
                    color: colorScheme.primary,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 32),
          Text(
            'Setup Complete!',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Your feeder is ready to use',
            style: TextStyle(
              fontSize: 16,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
