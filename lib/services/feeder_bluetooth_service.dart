/// Bluetooth service for Ornimetrics OS device pairing and commands
/// Handles device discovery, pairing, WiFi configuration, and account linking

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/feeder_models.dart';

/// Service UUID for Ornimetrics OS devices
const String kOrnimetricsServiceUuid = '00001101-0000-1000-8000-00805f9b34fb';
const String kDeviceNamePrefix = 'Ornimetrics-';
const Duration kScanTimeout = Duration(seconds: 15);
const Duration kConnectionTimeout = Duration(seconds: 30);
const Duration kCommandTimeout = Duration(seconds: 10);

class FeederBluetoothService {
  static final FeederBluetoothService instance = FeederBluetoothService._();
  FeederBluetoothService._();

  // State notifiers
  final ValueNotifier<bool> isScanning = ValueNotifier(false);
  final ValueNotifier<bool> isConnected = ValueNotifier(false);
  final ValueNotifier<List<OrnimetricsDevice>> discoveredDevices = ValueNotifier([]);
  final ValueNotifier<SetupStep> currentStep = ValueNotifier(SetupStep.scanning);
  final ValueNotifier<String?> errorMessage = ValueNotifier(null);
  final ValueNotifier<PairedFeeder?> currentDevice = ValueNotifier(null);

  // Internal state
  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _writeCharacteristic;
  BluetoothCharacteristic? _readCharacteristic;
  StreamSubscription<List<int>>? _notificationSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionStateSubscription;
  String? _sessionToken;
  DeviceWelcome? _welcomeMessage;
  final StreamController<Map<String, dynamic>> _responseController =
      StreamController.broadcast();

  // Response buffer for incoming data
  final StringBuffer _responseBuffer = StringBuffer();

  /// Check if Bluetooth is available and enabled
  Future<bool> isBluetoothAvailable() async {
    if (kIsWeb) return false;
    if (!Platform.isAndroid && !Platform.isIOS) return false;

    try {
      final isSupported = await FlutterBluePlus.isSupported;
      if (!isSupported) return false;

      final state = await FlutterBluePlus.adapterState.first;
      return state == BluetoothAdapterState.on;
    } catch (e) {
      debugPrint('FeederBluetoothService: Error checking Bluetooth: $e');
      return false;
    }
  }

  /// Request Bluetooth permissions and turn on if needed
  Future<bool> requestPermissions() async {
    try {
      if (Platform.isAndroid) {
        await FlutterBluePlus.turnOn();
      }
      return await isBluetoothAvailable();
    } catch (e) {
      debugPrint('FeederBluetoothService: Error requesting permissions: $e');
      return false;
    }
  }

  /// Start scanning for Ornimetrics devices
  Future<void> startScan() async {
    if (isScanning.value) return;

    try {
      errorMessage.value = null;
      isScanning.value = true;
      currentStep.value = SetupStep.scanning;
      discoveredDevices.value = [];

      // Stop any existing scan
      await FlutterBluePlus.stopScan();

      // Listen for scan results
      FlutterBluePlus.scanResults.listen((results) {
        final devices = <OrnimetricsDevice>[];
        for (final result in results) {
          final name = result.device.platformName;
          if (name.startsWith(kDeviceNamePrefix)) {
            devices.add(OrnimetricsDevice(
              id: result.device.remoteId.str,
              name: name,
              hostname: name.replaceFirst(kDeviceNamePrefix, ''),
              rssi: result.rssi,
              isConnectable: result.advertisementData.connectable,
            ));
          }
        }
        discoveredDevices.value = devices;
      });

      // Start scanning with timeout
      await FlutterBluePlus.startScan(
        timeout: kScanTimeout,
        androidUsesFineLocation: true,
      );

      // Wait for scan to complete
      await Future.delayed(kScanTimeout);
    } catch (e) {
      errorMessage.value = 'Scan failed: ${e.toString()}';
      debugPrint('FeederBluetoothService: Scan error: $e');
    } finally {
      isScanning.value = false;
    }
  }

  /// Stop scanning
  Future<void> stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (e) {
      debugPrint('FeederBluetoothService: Error stopping scan: $e');
    } finally {
      isScanning.value = false;
    }
  }

  /// Connect to a discovered device
  Future<bool> connectToDevice(OrnimetricsDevice device) async {
    try {
      errorMessage.value = null;
      currentStep.value = SetupStep.connecting;

      // Get the BluetoothDevice
      final bluetoothDevice = BluetoothDevice.fromId(device.id);
      _connectedDevice = bluetoothDevice;

      // Listen for connection state changes
      _connectionStateSubscription = bluetoothDevice.connectionState.listen((state) {
        isConnected.value = state == BluetoothConnectionState.connected;
        if (state == BluetoothConnectionState.disconnected) {
          _handleDisconnect();
        }
      });

      // Connect with timeout
      await bluetoothDevice.connect(
        timeout: kConnectionTimeout,
        autoConnect: false,
      );

      // Discover services
      final services = await bluetoothDevice.discoverServices();

      // Find the Ornimetrics service
      BluetoothService? ornimetricsService;
      for (final service in services) {
        if (service.uuid.toString().toLowerCase() == kOrnimetricsServiceUuid) {
          ornimetricsService = service;
          break;
        }
      }

      if (ornimetricsService == null) {
        // Try to find any service with readable/writable characteristics
        for (final service in services) {
          for (final char in service.characteristics) {
            if (char.properties.write && _writeCharacteristic == null) {
              _writeCharacteristic = char;
            }
            if (char.properties.notify && _readCharacteristic == null) {
              _readCharacteristic = char;
            }
          }
        }
      } else {
        for (final char in ornimetricsService.characteristics) {
          if (char.properties.write || char.properties.writeWithoutResponse) {
            _writeCharacteristic = char;
          }
          if (char.properties.notify || char.properties.indicate) {
            _readCharacteristic = char;
          }
        }
      }

      if (_writeCharacteristic == null || _readCharacteristic == null) {
        throw Exception('Required characteristics not found');
      }

      // Subscribe to notifications
      await _readCharacteristic!.setNotifyValue(true);
      _notificationSubscription = _readCharacteristic!.onValueReceived.listen(_handleNotification);

      isConnected.value = true;

      // Wait for welcome message
      final welcome = await _waitForMessage('welcome', timeout: const Duration(seconds: 5));
      if (welcome != null) {
        _welcomeMessage = DeviceWelcome.fromJson(welcome);
      }

      return true;
    } catch (e) {
      errorMessage.value = 'Connection failed: ${e.toString()}';
      debugPrint('FeederBluetoothService: Connection error: $e');
      await disconnect();
      return false;
    }
  }

  /// Handle incoming notifications
  void _handleNotification(List<int> data) {
    try {
      final text = utf8.decode(data);
      _responseBuffer.write(text);

      // Check for complete JSON messages (terminated by newline)
      final content = _responseBuffer.toString();
      final lines = content.split('\n');

      for (int i = 0; i < lines.length - 1; i++) {
        final line = lines[i].trim();
        if (line.isNotEmpty) {
          try {
            final json = jsonDecode(line) as Map<String, dynamic>;
            _responseController.add(json);
          } catch (e) {
            debugPrint('FeederBluetoothService: Failed to parse response: $line');
          }
        }
      }

      // Keep any incomplete message in the buffer
      _responseBuffer.clear();
      if (lines.last.isNotEmpty) {
        _responseBuffer.write(lines.last);
      }
    } catch (e) {
      debugPrint('FeederBluetoothService: Notification handling error: $e');
    }
  }

  /// Wait for a specific message type
  Future<Map<String, dynamic>?> _waitForMessage(String type, {Duration timeout = kCommandTimeout}) async {
    try {
      final response = await _responseController.stream
          .firstWhere((msg) => msg['type'] == type || msg['type'] == 'error')
          .timeout(timeout);

      if (response['type'] == 'error') {
        throw Exception(response['message'] ?? 'Unknown error');
      }

      return response;
    } catch (e) {
      debugPrint('FeederBluetoothService: Wait for message error: $e');
      return null;
    }
  }

  /// Send a command to the device
  Future<bool> _sendCommand(Map<String, dynamic> command) async {
    if (_writeCharacteristic == null) {
      errorMessage.value = 'Not connected to device';
      return false;
    }

    try {
      final json = jsonEncode(command) + '\n';
      final bytes = utf8.encode(json);
      await _writeCharacteristic!.write(bytes, withoutResponse: false);
      return true;
    } catch (e) {
      errorMessage.value = 'Failed to send command: ${e.toString()}';
      debugPrint('FeederBluetoothService: Send command error: $e');
      return false;
    }
  }

  /// Pair with the connected device
  Future<PairingSession?> pair({
    required String appId,
    required String deviceModel,
    required String appVersion,
  }) async {
    try {
      currentStep.value = SetupStep.pairing;
      errorMessage.value = null;

      final command = {
        'type': 'pair',
        'app_id': appId,
        'device_model': deviceModel,
        'app_version': appVersion,
      };

      if (!await _sendCommand(command)) {
        return null;
      }

      final response = await _waitForMessage('pair_success');
      if (response == null) {
        errorMessage.value = 'Pairing failed - no response';
        return null;
      }

      final session = PairingSession.fromJson(response);
      _sessionToken = session.sessionToken;
      return session;
    } catch (e) {
      errorMessage.value = 'Pairing failed: ${e.toString()}';
      debugPrint('FeederBluetoothService: Pairing error: $e');
      return null;
    }
  }

  /// Link device to user account
  Future<bool> linkAccount({
    required String userId,
    required String accountEmail,
    required String accountToken,
    required String feederName,
  }) async {
    if (_sessionToken == null) {
      errorMessage.value = 'Not paired - please pair first';
      return false;
    }

    try {
      currentStep.value = SetupStep.linkingAccount;
      errorMessage.value = null;

      final command = {
        'type': 'link_account',
        'session_token': _sessionToken,
        'user_id': userId,
        'account_email': accountEmail,
        'account_token': accountToken,
        'feeder_name': feederName,
      };

      if (!await _sendCommand(command)) {
        return false;
      }

      final response = await _waitForMessage('account_linked');
      return response != null;
    } catch (e) {
      errorMessage.value = 'Account linking failed: ${e.toString()}';
      debugPrint('FeederBluetoothService: Account linking error: $e');
      return false;
    }
  }

  /// Configure WiFi on the device
  Future<WifiConfigResult?> configureWifi({
    required String ssid,
    required String password,
  }) async {
    if (_sessionToken == null) {
      errorMessage.value = 'Not paired - please pair first';
      return null;
    }

    try {
      currentStep.value = SetupStep.configuringWifi;
      errorMessage.value = null;

      final command = {
        'type': 'configure_wifi',
        'session_token': _sessionToken,
        'ssid': ssid,
        'password': password,
      };

      if (!await _sendCommand(command)) {
        return null;
      }

      final response = await _waitForMessage('wifi_configured', timeout: const Duration(seconds: 30));
      if (response == null) {
        errorMessage.value = 'WiFi configuration failed - no response';
        return null;
      }

      return WifiConfigResult.fromJson(response);
    } catch (e) {
      errorMessage.value = 'WiFi configuration failed: ${e.toString()}';
      debugPrint('FeederBluetoothService: WiFi config error: $e');
      return null;
    }
  }

  /// Update device settings
  Future<bool> updateSettings({
    String? deviceName,
    String? feederName,
    bool? individualRecognition,
    bool? autoTraining,
    bool? camera3d,
  }) async {
    if (_sessionToken == null) {
      errorMessage.value = 'Not paired - please pair first';
      return false;
    }

    try {
      errorMessage.value = null;

      final settings = <String, dynamic>{};
      if (deviceName != null) settings['device_name'] = deviceName;
      if (feederName != null) settings['feeder_name'] = feederName;

      final features = <String, bool>{};
      if (individualRecognition != null) features['individual_recognition'] = individualRecognition;
      if (autoTraining != null) features['auto_training'] = autoTraining;
      if (camera3d != null) features['3d_camera'] = camera3d;

      if (features.isNotEmpty) {
        settings['features'] = features;
      }

      final command = {
        'type': 'update_settings',
        'session_token': _sessionToken,
        'settings': settings,
      };

      if (!await _sendCommand(command)) {
        return false;
      }

      final response = await _waitForMessage('settings_updated');
      return response != null && response['success'] == true;
    } catch (e) {
      errorMessage.value = 'Settings update failed: ${e.toString()}';
      debugPrint('FeederBluetoothService: Settings update error: $e');
      return false;
    }
  }

  /// Get device status
  Future<FeederDeviceStatus?> getDeviceStatus() async {
    try {
      currentStep.value = SetupStep.verifying;
      errorMessage.value = null;

      final command = {'type': 'get_status'};

      if (!await _sendCommand(command)) {
        return null;
      }

      final response = await _waitForMessage('status');
      if (response == null) {
        return null;
      }

      return FeederDeviceStatus.fromJson(response);
    } catch (e) {
      errorMessage.value = 'Failed to get status: ${e.toString()}';
      debugPrint('FeederBluetoothService: Get status error: $e');
      return null;
    }
  }

  /// Complete setup and save paired device
  Future<PairedFeeder?> completeSetup({
    required String userId,
    required String feederName,
  }) async {
    try {
      currentStep.value = SetupStep.complete;

      final status = await getDeviceStatus();
      if (status == null) {
        errorMessage.value = 'Failed to verify device status';
        return null;
      }

      final pairedFeeder = PairedFeeder(
        deviceId: status.deviceId,
        deviceName: status.deviceName,
        feederName: feederName,
        staticIp: status.staticIp ?? '192.168.1.200',
        version: status.version,
        pairedAt: DateTime.now(),
        userId: userId,
      );

      await _savePairedDevice(pairedFeeder);
      currentDevice.value = pairedFeeder;

      return pairedFeeder;
    } catch (e) {
      errorMessage.value = 'Setup completion failed: ${e.toString()}';
      debugPrint('FeederBluetoothService: Complete setup error: $e');
      return null;
    }
  }

  /// Disconnect from the current device
  Future<void> disconnect() async {
    try {
      _notificationSubscription?.cancel();
      _notificationSubscription = null;
      _connectionStateSubscription?.cancel();
      _connectionStateSubscription = null;

      if (_connectedDevice != null) {
        await _connectedDevice!.disconnect();
      }
    } catch (e) {
      debugPrint('FeederBluetoothService: Disconnect error: $e');
    } finally {
      _handleDisconnect();
    }
  }

  void _handleDisconnect() {
    _connectedDevice = null;
    _writeCharacteristic = null;
    _readCharacteristic = null;
    _sessionToken = null;
    _welcomeMessage = null;
    _responseBuffer.clear();
    isConnected.value = false;
  }

  // ===== PAIRED DEVICE PERSISTENCE =====

  static const String _pairedDevicesKey = 'paired_ornimetrics_devices';

  Future<void> _savePairedDevice(PairedFeeder device) async {
    final prefs = await SharedPreferences.getInstance();
    final devices = await loadPairedDevices();

    // Remove existing device with same ID
    devices.removeWhere((d) => d.deviceId == device.deviceId);
    devices.add(device);

    final json = devices.map((d) => d.toJson()).toList();
    await prefs.setString(_pairedDevicesKey, jsonEncode(json));
  }

  Future<List<PairedFeeder>> loadPairedDevices() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = prefs.getString(_pairedDevicesKey);
      if (data == null) return [];

      final List<dynamic> json = jsonDecode(data);
      return json.map((e) => PairedFeeder.fromJson(e)).toList();
    } catch (e) {
      debugPrint('FeederBluetoothService: Failed to load paired devices: $e');
      return [];
    }
  }

  Future<PairedFeeder?> getPairedDevice(String deviceId) async {
    final devices = await loadPairedDevices();
    try {
      return devices.firstWhere((d) => d.deviceId == deviceId);
    } catch (_) {
      return null;
    }
  }

  Future<void> removePairedDevice(String deviceId) async {
    final prefs = await SharedPreferences.getInstance();
    final devices = await loadPairedDevices();
    devices.removeWhere((d) => d.deviceId == deviceId);

    final json = devices.map((d) => d.toJson()).toList();
    await prefs.setString(_pairedDevicesKey, jsonEncode(json));

    if (currentDevice.value?.deviceId == deviceId) {
      currentDevice.value = null;
    }
  }

  /// Load the first paired device for current user
  Future<void> loadCurrentDevice(String userId) async {
    final devices = await loadPairedDevices();
    final userDevices = devices.where((d) => d.userId == userId).toList();
    if (userDevices.isNotEmpty) {
      currentDevice.value = userDevices.first;
    }
  }

  /// Get welcome message info
  DeviceWelcome? get welcomeMessage => _welcomeMessage;

  /// Dispose of resources
  void dispose() {
    _notificationSubscription?.cancel();
    _connectionStateSubscription?.cancel();
    _responseController.close();
    isScanning.dispose();
    isConnected.dispose();
    discoveredDevices.dispose();
    currentStep.dispose();
    errorMessage.dispose();
    currentDevice.dispose();
  }
}
