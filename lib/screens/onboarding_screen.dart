import 'dart:io';
import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart';

class OnboardingScreen extends StatefulWidget {
  final VoidCallback onComplete;

  const OnboardingScreen({super.key, required this.onComplete});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  // Animation controllers
  late AnimationController _breathingController;
  late AnimationController _floatingController;
  late AnimationController _pulseController;

  // Settings state
  bool _darkMode = false;
  Color _selectedColor = Colors.green;
  bool _hapticsEnabled = true;
  bool _autoRefresh = false;
  double _refreshInterval = 60.0;
  bool _reduceMotion = false;
  bool _showNotifications = true;
  String _temperatureUnit = 'celsius';
  double _textScale = 1.0;

  // Additional customization
  String _distanceUnit = 'km';
  bool _compactMode = false;
  int _defaultTab = 0;
  int _photoGridColumns = 2;

  // Live update settings
  bool _liveUpdatesEnabled = true;
  bool _liveUpdateSound = true;
  bool _liveUpdateVibration = true;
  String _liveUpdateDisplayMode = 'banner';
  List<String> _liveUpdateTypes = ['new_detection', 'rare_species', 'community'];

  // Additional display settings
  bool _showDetectionTime = true;
  bool _showConfidence = true;
  String _sortOrder = 'newest';

  // Auth state
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLogin = true;
  bool _authLoading = false;
  String? _authError;
  bool _authSuccess = false;

  final List<Color> _colorOptions = [
    Colors.green,
    Colors.blue,
    Colors.purple,
    Colors.orange,
    Colors.pink,
    Colors.teal,
    Colors.indigo,
    Colors.red,
    Colors.amber,
    Colors.cyan,
    Colors.deepPurple,
    Colors.lime,
  ];

  @override
  void initState() {
    super.initState();
    _loadCurrentSettings();

    // Breathing animation (slow, subtle)
    _breathingController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);

    // Floating animation for decorative elements
    _floatingController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat(reverse: true);

    // Pulse animation for highlights
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  Future<void> _loadCurrentSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _darkMode = prefs.getBool('pref_dark_mode') ?? false;
      _hapticsEnabled = prefs.getBool('pref_haptics_enabled') ?? true;
      _autoRefresh = prefs.getBool('pref_auto_refresh_enabled') ?? false;
      _refreshInterval = prefs.getDouble('pref_auto_refresh_interval') ?? 60.0;
      _reduceMotion = prefs.getBool('pref_reduce_motion') ?? false;
      _showNotifications = prefs.getBool('pref_notifications') ?? true;
      _temperatureUnit = prefs.getString('pref_temp_unit') ?? 'celsius';
      _textScale = prefs.getDouble('pref_text_scale') ?? 1.0;
      _distanceUnit = prefs.getString('pref_distance_unit') ?? 'km';
      _compactMode = prefs.getBool('pref_compact_mode') ?? false;
      _defaultTab = prefs.getInt('pref_default_tab') ?? 0;
      _photoGridColumns = prefs.getInt('pref_photo_grid_columns') ?? 2;
      // Live update settings
      _liveUpdatesEnabled = prefs.getBool('pref_live_updates_enabled') ?? true;
      _liveUpdateSound = prefs.getBool('pref_live_update_sound') ?? true;
      _liveUpdateVibration = prefs.getBool('pref_live_update_vibration') ?? true;
      _liveUpdateDisplayMode = prefs.getString('pref_live_update_display_mode') ?? 'banner';
      _liveUpdateTypes = prefs.getStringList('pref_live_update_types') ?? ['new_detection', 'rare_species', 'community'];
      // Display settings
      _showDetectionTime = prefs.getBool('pref_show_detection_time') ?? true;
      _showConfidence = prefs.getBool('pref_show_confidence') ?? true;
      _sortOrder = prefs.getString('pref_sort_order') ?? 'newest';
      final seedValue = prefs.getInt('pref_seed_color');
      if (seedValue != null) {
        _selectedColor = Color(seedValue);
      }
    });
    // Apply text scale immediately for live preview during onboarding rerun
    textScaleNotifier.value = _textScale;
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('pref_dark_mode', _darkMode);
    await prefs.setBool('pref_haptics_enabled', _hapticsEnabled);
    await prefs.setBool('pref_auto_refresh_enabled', _autoRefresh);
    await prefs.setDouble('pref_auto_refresh_interval', _refreshInterval);
    await prefs.setBool('pref_reduce_motion', _reduceMotion);
    await prefs.setBool('pref_notifications', _showNotifications);
    await prefs.setString('pref_temp_unit', _temperatureUnit);
    await prefs.setDouble('pref_text_scale', _textScale);
    await prefs.setInt('pref_seed_color', _selectedColor.value);
    await prefs.setString('pref_distance_unit', _distanceUnit);
    await prefs.setBool('pref_compact_mode', _compactMode);
    await prefs.setInt('pref_default_tab', _defaultTab);
    await prefs.setInt('pref_photo_grid_columns', _photoGridColumns);
    // Live update settings
    await prefs.setBool('pref_live_updates_enabled', _liveUpdatesEnabled);
    await prefs.setBool('pref_live_update_sound', _liveUpdateSound);
    await prefs.setBool('pref_live_update_vibration', _liveUpdateVibration);
    await prefs.setString('pref_live_update_display_mode', _liveUpdateDisplayMode);
    await prefs.setStringList('pref_live_update_types', _liveUpdateTypes);
    // Display settings
    await prefs.setBool('pref_show_detection_time', _showDetectionTime);
    await prefs.setBool('pref_show_confidence', _showConfidence);
    await prefs.setString('pref_sort_order', _sortOrder);

    themeNotifier.value = _darkMode ? ThemeMode.dark : ThemeMode.light;
    hapticsEnabledNotifier.value = _hapticsEnabled;
    seedColorNotifier.value = _selectedColor;
    autoRefreshEnabledNotifier.value = _autoRefresh;
    autoRefreshIntervalNotifier.value = _refreshInterval;
    textScaleNotifier.value = _textScale;
    distanceUnitNotifier.value = _distanceUnit;
    compactModeNotifier.value = _compactMode;
    defaultTabNotifier.value = _defaultTab;
    photoGridColumnsNotifier.value = _photoGridColumns;
    liveUpdatesEnabledNotifier.value = _liveUpdatesEnabled;
    liveUpdateSoundNotifier.value = _liveUpdateSound;
    liveUpdateVibrationNotifier.value = _liveUpdateVibration;
    liveUpdateDisplayModeNotifier.value = _liveUpdateDisplayMode;
    liveUpdateTypesNotifier.value = _liveUpdateTypes;
  }

  void _nextPage() {
    _haptic();
    if (_currentPage < 4) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOutCubic,
      );
    } else {
      _completeOnboarding();
    }
  }

  void _previousPage() {
    _haptic();
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  void _haptic() {
    if (_hapticsEnabled) {
      if (Platform.isIOS) {
        HapticFeedback.lightImpact();
      } else {
        HapticFeedback.selectionClick();
      }
    }
  }

  Future<void> _completeOnboarding() async {
    _haptic();
    await _saveSettings();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_complete', true);
    widget.onComplete();
  }

  Future<void> _handleAuth() async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      setState(() => _authError = 'Please enter email and password');
      return;
    }

    setState(() {
      _authLoading = true;
      _authError = null;
    });

    try {
      if (_isLogin) {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
      } else {
        await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
      }
      setState(() {
        _authSuccess = true;
        _authLoading = false;
      });
      _haptic();
    } on FirebaseAuthException catch (e) {
      setState(() {
        _authError = e.message ?? 'Authentication failed';
        _authLoading = false;
      });
    } catch (e) {
      setState(() {
        _authError = e.toString();
        _authLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _breathingController.dispose();
    _floatingController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _selectedColor,
      brightness: _darkMode ? Brightness.dark : Brightness.light,
    );

    return Theme(
      data: Theme.of(context).copyWith(colorScheme: colorScheme),
      child: Scaffold(
        body: Stack(
          children: [
            // Animated breathing background
            _buildAnimatedBackground(colorScheme),

            // Main content
            SafeArea(
              child: Column(
                children: [
                  // Progress indicator
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: List.generate(5, (i) {
                        return Expanded(
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 400),
                            height: 4,
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            decoration: BoxDecoration(
                              color: i <= _currentPage
                                  ? colorScheme.primary
                                  : colorScheme.primary.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(2),
                              boxShadow: i <= _currentPage
                                  ? [
                                BoxShadow(
                                  color: colorScheme.primary.withOpacity(0.4),
                                  blurRadius: 4,
                                  spreadRadius: 0,
                                )
                              ]
                                  : null,
                            ),
                          ),
                        );
                      }),
                    ),
                  ),

                  // Pages
                  Expanded(
                    child: PageView(
                      controller: _pageController,
                      physics: const NeverScrollableScrollPhysics(),
                      onPageChanged: (i) => setState(() => _currentPage = i),
                      children: [
                        _buildWelcomePage(colorScheme),
                        _buildThemePage(colorScheme),
                        _buildSettingsPage(colorScheme),
                        _buildAccountPage(colorScheme),
                        _buildDonePage(colorScheme),
                      ],
                    ),
                  ),

                  // Navigation buttons
                  _buildNavigationButtons(colorScheme),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnimatedBackground(ColorScheme colorScheme) {
    return AnimatedBuilder(
      animation: Listenable.merge([_breathingController, _floatingController]),
      builder: (context, child) {
        final breathValue = _breathingController.value;
        final floatValue = _floatingController.value;

        return Stack(
          children: [
            // Base gradient
            AnimatedContainer(
              duration: const Duration(milliseconds: 500),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    colorScheme.surface,
                    colorScheme.primaryContainer.withOpacity(0.3),
                    colorScheme.surface,
                  ],
                ),
              ),
            ),

            // Breathing orb 1 (top right)
            Positioned(
              top: -50 + (breathValue * 20),
              right: -80 + (floatValue * 30),
              child: _buildBreathingOrb(
                size: 300,
                color: colorScheme.primary.withOpacity(0.15 + breathValue * 0.1),
                blur: 80 + breathValue * 20,
              ),
            ),

            // Breathing orb 2 (bottom left)
            Positioned(
              bottom: -100 + (floatValue * 40),
              left: -60 + (breathValue * 25),
              child: _buildBreathingOrb(
                size: 350,
                color: colorScheme.tertiary.withOpacity(0.12 + floatValue * 0.08),
                blur: 100 + floatValue * 30,
              ),
            ),

            // Breathing orb 3 (center)
            Positioned(
              top: MediaQuery.of(context).size.height * 0.4 + (breathValue * 15),
              left: MediaQuery.of(context).size.width * 0.3 + (floatValue * 20),
              child: _buildBreathingOrb(
                size: 200,
                color: colorScheme.secondary.withOpacity(0.1 + breathValue * 0.05),
                blur: 60 + breathValue * 15,
              ),
            ),

            // Floating particles
            ...List.generate(6, (i) {
              final angle = (i * math.pi / 3) + (floatValue * math.pi * 0.2);
              final radius = 150 + (breathValue * 20);
              return Positioned(
                top: MediaQuery.of(context).size.height * 0.5 +
                    math.sin(angle) * radius,
                left: MediaQuery.of(context).size.width * 0.5 +
                    math.cos(angle) * radius -
                    10,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 300),
                  opacity: 0.3 + breathValue * 0.3,
                  child: Container(
                    width: 8 + (i * 2),
                    height: 8 + (i * 2),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withOpacity(0.4),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: colorScheme.primary.withOpacity(0.3),
                          blurRadius: 8,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ],
        );
      },
    );
  }

  Widget _buildBreathingOrb({
    required double size,
    required Color color,
    required double blur,
  }) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color,
            blurRadius: blur,
            spreadRadius: 0,
          ),
        ],
      ),
    );
  }

  Widget _buildNavigationButtons(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          AnimatedOpacity(
            duration: const Duration(milliseconds: 300),
            opacity: _currentPage > 0 ? 1 : 0,
            child: AnimatedSlide(
              duration: const Duration(milliseconds: 300),
              offset: _currentPage > 0 ? Offset.zero : const Offset(-0.5, 0),
              child: TextButton.icon(
                onPressed: _currentPage > 0 ? _previousPage : null,
                icon: const Icon(Icons.arrow_back_rounded),
                label: const Text('Back'),
              ),
            ),
          ),
          const Spacer(),
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              final pulse = _currentPage == 4 ? 1 + (_pulseController.value * 0.05) : 1.0;
              return Transform.scale(
                scale: pulse,
                child: FilledButton.icon(
                  onPressed: _nextPage,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                  icon: Icon(
                    _currentPage == 4 ? Icons.rocket_launch_rounded : Icons.arrow_forward_rounded,
                  ),
                  label: Text(_currentPage == 4 ? 'Get Started' : 'Next'),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildWelcomePage(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Animated bird icon with floating effect
          AnimatedBuilder(
            animation: _floatingController,
            builder: (context, child) {
              return Transform.translate(
                offset: Offset(0, -10 + (_floatingController.value * 20)),
                child: child,
              );
            },
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 1000),
              curve: Curves.elasticOut,
              builder: (_, value, child) => Transform.scale(
                scale: value,
                child: child,
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Glow effect
                  AnimatedBuilder(
                    animation: _breathingController,
                    builder: (context, child) {
                      return Container(
                        width: 160 + (_breathingController.value * 20),
                        height: 160 + (_breathingController.value * 20),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: colorScheme.primary.withOpacity(0.3),
                              blurRadius: 40 + (_breathingController.value * 20),
                              spreadRadius: 10,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  // Icon container
                  Container(
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          colorScheme.primaryContainer,
                          colorScheme.primaryContainer.withOpacity(0.8),
                        ],
                      ),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: colorScheme.primary.withOpacity(0.3),
                        width: 2,
                      ),
                    ),
                    child: Icon(
                      Icons.flutter_dash,
                      size: 80,
                      color: colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 48),

          // Title with staggered animation
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 800),
            curve: Curves.easeOutCubic,
            builder: (_, value, child) => Opacity(
              opacity: value,
              child: Transform.translate(
                offset: Offset(0, 30 * (1 - value)),
                child: child,
              ),
            ),
            child: ShaderMask(
              shaderCallback: (bounds) => LinearGradient(
                colors: [
                  colorScheme.primary,
                  colorScheme.tertiary,
                ],
              ).createShader(bounds),
              child: Text(
                'Welcome to\nOrnimetrics',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  height: 1.1,
                  letterSpacing: -1,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Subtitle
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 800),
            curve: Curves.easeOut,
            builder: (_, value, child) => Opacity(
              opacity: value,
              child: child,
            ),
            child: Text(
              'Track bird detections, discover patterns,\nand join our birding community.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ),

          const SizedBox(height: 32),

          // Feature pills
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 1000),
            curve: Curves.easeOut,
            builder: (_, value, child) => Opacity(
              opacity: value,
              child: Transform.translate(
                offset: Offset(0, 20 * (1 - value)),
                child: child,
              ),
            ),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                _buildFeaturePill(colorScheme, Icons.analytics_outlined, 'Smart Analytics'),
                _buildFeaturePill(colorScheme, Icons.cloud_outlined, 'Weather Insights'),
                _buildFeaturePill(colorScheme, Icons.people_outline, 'Community'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeaturePill(ColorScheme colorScheme, IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withOpacity(0.5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colorScheme.primary.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: colorScheme.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThemePage(ColorScheme colorScheme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPageHeader(
            colorScheme,
            'Customize Your Theme',
            'Make it yours',
            Icons.palette_outlined,
          ),
          const SizedBox(height: 32),

          // Dark mode toggle with animation
          _buildAnimatedSettingCard(
            colorScheme: colorScheme,
            icon: _darkMode ? Icons.dark_mode : Icons.light_mode,
            iconColor: _darkMode ? Colors.indigo : Colors.amber,
            title: 'Appearance',
            subtitle: _darkMode ? 'Dark mode' : 'Light mode',
            trailing: GestureDetector(
              onTap: () {
                _haptic();
                setState(() => _darkMode = !_darkMode);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 60,
                height: 32,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: _darkMode ? colorScheme.primary : colorScheme.surfaceContainerHighest,
                ),
                child: AnimatedAlign(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  alignment: _darkMode ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _darkMode ? Colors.white : colorScheme.primary,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    child: Icon(
                      _darkMode ? Icons.dark_mode : Icons.light_mode,
                      size: 14,
                      color: _darkMode ? colorScheme.primary : Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Color picker with larger grid
          Text(
            'Accent Color',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Choose a color that represents you',
            style: TextStyle(
              fontSize: 14,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),

          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 6,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
            ),
            itemCount: _colorOptions.length,
            itemBuilder: (context, index) {
              final color = _colorOptions[index];
              final isSelected = _selectedColor.value == color.value;
              return GestureDetector(
                onTap: () {
                  _haptic();
                  setState(() => _selectedColor = color);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? Colors.white : Colors.transparent,
                      width: 3,
                    ),
                    boxShadow: isSelected
                        ? [
                      BoxShadow(
                        color: color.withOpacity(0.5),
                        blurRadius: 12,
                        spreadRadius: 2,
                      ),
                    ]
                        : [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                  child: AnimatedScale(
                    scale: isSelected ? 1.1 : 1.0,
                    duration: const Duration(milliseconds: 200),
                    child: isSelected
                        ? const Icon(Icons.check, color: Colors.white, size: 24)
                        : null,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 32),

          // Text scale - updates live
          _buildSliderSetting(
            colorScheme: colorScheme,
            icon: Icons.text_fields,
            title: 'Text Size',
            value: _textScale,
            min: 0.8,
            max: 1.4,
            divisions: 6,
            label: '${(_textScale * 100).round()}%',
            onChanged: (v) {
              setState(() => _textScale = v);
              textScaleNotifier.value = v; // Apply immediately for live preview
            },
          ),
          const SizedBox(height: 12),

          // Photo grid columns
          _buildSliderSetting(
            colorScheme: colorScheme,
            icon: Icons.grid_view,
            title: 'Photo Grid Columns',
            value: _photoGridColumns.toDouble(),
            min: 2,
            max: 4,
            divisions: 2,
            label: '$_photoGridColumns columns',
            onChanged: (v) {
              _haptic();
              setState(() => _photoGridColumns = v.round());
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPageHeader(
      ColorScheme colorScheme,
      String title,
      String subtitle,
      IconData icon,
      ) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: colorScheme.primary, size: 28),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 14,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAnimatedSettingCard({
    required ColorScheme colorScheme,
    required IconData icon,
    Color? iconColor,
    required String title,
    required String subtitle,
    required Widget trailing,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outline.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: (iconColor ?? colorScheme.primary).withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor ?? colorScheme.primary, size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          trailing,
        ],
      ),
    );
  }

  Widget _buildSliderSetting({
    required ColorScheme colorScheme,
    required IconData icon,
    required String title,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String label,
    required ValueChanged<double> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outline.withOpacity(0.1)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(icon, color: colorScheme.primary, size: 22),
              const SizedBox(width: 12),
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: colorScheme.primary,
              inactiveTrackColor: colorScheme.primary.withOpacity(0.2),
              thumbColor: colorScheme.primary,
              overlayColor: colorScheme.primary.withOpacity(0.1),
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsPage(ColorScheme colorScheme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPageHeader(
            colorScheme,
            'App Settings',
            'Configure your experience',
            Icons.tune_rounded,
          ),
          const SizedBox(height: 32),

          // Haptics
          _buildSwitchSetting(
            colorScheme: colorScheme,
            icon: Icons.vibration,
            title: 'Haptic Feedback',
            subtitle: 'Feel subtle vibrations',
            value: _hapticsEnabled,
            onChanged: (v) {
              if (v) _haptic();
              setState(() => _hapticsEnabled = v);
            },
          ),
          const SizedBox(height: 12),

          // Notifications
          _buildSwitchSetting(
            colorScheme: colorScheme,
            icon: Icons.notifications_outlined,
            title: 'Notifications',
            subtitle: 'Get detection alerts',
            value: _showNotifications,
            onChanged: (v) {
              _haptic();
              setState(() => _showNotifications = v);
            },
          ),
          const SizedBox(height: 12),

          // Reduce motion
          _buildSwitchSetting(
            colorScheme: colorScheme,
            icon: Icons.animation,
            title: 'Reduce Motion',
            subtitle: 'Minimize animations',
            value: _reduceMotion,
            onChanged: (v) {
              _haptic();
              setState(() => _reduceMotion = v);
            },
          ),
          const SizedBox(height: 24),

          // Temperature unit
          Text(
            'Units',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          _buildSegmentedControl(
            colorScheme: colorScheme,
            value: _temperatureUnit,
            options: const ['celsius', 'fahrenheit'],
            labels: const ['Celsius (°C)', 'Fahrenheit (°F)'],
            onChanged: (v) {
              _haptic();
              setState(() => _temperatureUnit = v);
            },
          ),
          const SizedBox(height: 24),

          // Auto refresh
          _buildSwitchSetting(
            colorScheme: colorScheme,
            icon: Icons.sync,
            title: 'Auto Refresh',
            subtitle: 'Update data automatically',
            value: _autoRefresh,
            onChanged: (v) {
              _haptic();
              setState(() => _autoRefresh = v);
            },
          ),

          if (_autoRefresh) ...[
            const SizedBox(height: 12),
            _buildSliderSetting(
              colorScheme: colorScheme,
              icon: Icons.timer_outlined,
              title: 'Refresh Interval',
              value: _refreshInterval,
              min: 30,
              max: 300,
              divisions: 9,
              label: '${_refreshInterval.round()}s',
              onChanged: (v) => setState(() => _refreshInterval = v),
            ),
          ],

          const SizedBox(height: 24),

          // Display options section
          Text(
            'Display Options',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),

          // Compact mode
          _buildSwitchSetting(
            colorScheme: colorScheme,
            icon: Icons.view_compact_outlined,
            title: 'Compact Mode',
            subtitle: 'Denser UI layout',
            value: _compactMode,
            onChanged: (v) {
              _haptic();
              setState(() => _compactMode = v);
              compactModeNotifier.value = v;
            },
          ),
          const SizedBox(height: 12),

          // Show detection time
          _buildSwitchSetting(
            colorScheme: colorScheme,
            icon: Icons.access_time,
            title: 'Show Detection Time',
            subtitle: 'Display when birds were detected',
            value: _showDetectionTime,
            onChanged: (v) {
              _haptic();
              setState(() => _showDetectionTime = v);
            },
          ),
          const SizedBox(height: 12),

          // Show confidence
          _buildSwitchSetting(
            colorScheme: colorScheme,
            icon: Icons.verified_outlined,
            title: 'Show Confidence',
            subtitle: 'Display detection confidence percentage',
            value: _showConfidence,
            onChanged: (v) {
              _haptic();
              setState(() => _showConfidence = v);
            },
          ),
          const SizedBox(height: 24),

          // Sort order
          Text(
            'Default Sort Order',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          _buildSegmentedControl(
            colorScheme: colorScheme,
            value: _sortOrder,
            options: const ['newest', 'oldest', 'name'],
            labels: const ['Newest', 'Oldest', 'Name'],
            onChanged: (v) {
              _haptic();
              setState(() => _sortOrder = v);
            },
          ),
          const SizedBox(height: 24),

          // Distance unit
          Text(
            'Distance Unit',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          _buildSegmentedControl(
            colorScheme: colorScheme,
            value: _distanceUnit,
            options: const ['km', 'mi'],
            labels: const ['Kilometers', 'Miles'],
            onChanged: (v) {
              _haptic();
              setState(() => _distanceUnit = v);
              distanceUnitNotifier.value = v;
            },
          ),
          const SizedBox(height: 24),

          // Default tab
          Text(
            'Default Home Tab',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          _buildTabSelector(colorScheme),

          const SizedBox(height: 32),

          // Live Updates Section
          _buildLiveUpdatesSection(colorScheme),
        ],
      ),
    );
  }

  Widget _buildLiveUpdatesSection(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colorScheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.notifications_active, color: colorScheme.primary, size: 20),
            ),
            const SizedBox(width: 12),
            Text(
              'Live Updates',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Get real-time notifications when new detections occur',
          style: TextStyle(
            fontSize: 13,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),

        // Master toggle
        _buildSwitchSetting(
          colorScheme: colorScheme,
          icon: Icons.cell_tower,
          title: 'Enable Live Updates',
          subtitle: 'Receive real-time detection alerts',
          value: _liveUpdatesEnabled,
          onChanged: (v) {
            _haptic();
            setState(() => _liveUpdatesEnabled = v);
            liveUpdatesEnabledNotifier.value = v;
          },
        ),

        if (_liveUpdatesEnabled) ...[
          const SizedBox(height: 12),

          // Display mode
          Text(
            'Notification Style',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          _buildDisplayModeSelector(colorScheme),
          const SizedBox(height: 16),

          // Sound toggle
          _buildSwitchSetting(
            colorScheme: colorScheme,
            icon: Icons.volume_up,
            title: 'Sound',
            subtitle: 'Play sound for new detections',
            value: _liveUpdateSound,
            onChanged: (v) {
              _haptic();
              setState(() => _liveUpdateSound = v);
              liveUpdateSoundNotifier.value = v;
            },
          ),
          const SizedBox(height: 12),

          // Vibration toggle
          _buildSwitchSetting(
            colorScheme: colorScheme,
            icon: Icons.vibration,
            title: 'Vibration',
            subtitle: 'Vibrate for new detections',
            value: _liveUpdateVibration,
            onChanged: (v) {
              _haptic();
              setState(() => _liveUpdateVibration = v);
              liveUpdateVibrationNotifier.value = v;
            },
          ),
          const SizedBox(height: 16),

          // Notification types
          Text(
            'Show Notifications For',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          _buildNotificationTypeChips(colorScheme),
        ],
      ],
    );
  }

  Widget _buildDisplayModeSelector(ColorScheme colorScheme) {
    final modes = [
      ('banner', Icons.notifications, 'Banner'),
      ('popup', Icons.open_in_new, 'Popup'),
      ('minimal', Icons.minimize, 'Minimal'),
    ];

    return Row(
      children: modes.map((mode) {
        final isSelected = _liveUpdateDisplayMode == mode.$1;
        return Expanded(
          child: GestureDetector(
            onTap: () {
              _haptic();
              setState(() => _liveUpdateDisplayMode = mode.$1);
              liveUpdateDisplayModeNotifier.value = mode.$1;
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: EdgeInsets.only(right: mode.$1 != 'minimal' ? 8 : 0),
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: isSelected
                    ? colorScheme.primary
                    : colorScheme.surfaceContainerHighest.withOpacity(0.5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected
                      ? colorScheme.primary
                      : colorScheme.outline.withOpacity(0.2),
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    mode.$2,
                    size: 20,
                    color: isSelected
                        ? colorScheme.onPrimary
                        : colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    mode.$3,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                      color: isSelected
                          ? colorScheme.onPrimary
                          : colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildNotificationTypeChips(ColorScheme colorScheme) {
    final types = [
      ('new_detection', Icons.add_alert, 'New Detections'),
      ('rare_species', Icons.stars, 'Rare Species'),
      ('community', Icons.people, 'Community'),
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: types.map((type) {
        final isSelected = _liveUpdateTypes.contains(type.$1);
        return GestureDetector(
          onTap: () {
            _haptic();
            setState(() {
              if (isSelected) {
                _liveUpdateTypes.remove(type.$1);
              } else {
                _liveUpdateTypes.add(type.$1);
              }
            });
            liveUpdateTypesNotifier.value = List.from(_liveUpdateTypes);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected
                  ? colorScheme.primary.withOpacity(0.15)
                  : colorScheme.surfaceContainerHighest.withOpacity(0.5),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isSelected
                    ? colorScheme.primary
                    : colorScheme.outline.withOpacity(0.2),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isSelected ? Icons.check_circle : type.$2,
                  size: 18,
                  color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  type.$3,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    color: isSelected ? colorScheme.primary : colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTabSelector(ColorScheme colorScheme) {
    final tabs = [
      (0, Icons.dashboard, 'Dashboard'),
      (1, Icons.photo_camera_back_outlined, 'Recent'),
      (2, Icons.cloud_outlined, 'Environment'),
      (3, Icons.groups_2_outlined, 'Community'),
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: tabs.map((tab) {
        final isSelected = _defaultTab == tab.$1;
        return GestureDetector(
          onTap: () {
            _haptic();
            setState(() => _defaultTab = tab.$1);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isSelected
                  ? colorScheme.primary
                  : colorScheme.surfaceContainerHighest.withOpacity(0.5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected
                    ? colorScheme.primary
                    : colorScheme.outline.withOpacity(0.2),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  tab.$2,
                  size: 18,
                  color: isSelected
                      ? colorScheme.onPrimary
                      : colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text(
                  tab.$3,
                  style: TextStyle(
                    color: isSelected
                        ? colorScheme.onPrimary
                        : colorScheme.onSurface,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSwitchSetting({
    required ColorScheme colorScheme,
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colorScheme.outline.withOpacity(0.1)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colorScheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: colorScheme.primary, size: 22),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Switch.adaptive(
              value: value,
              onChanged: onChanged,
              activeColor: colorScheme.primary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSegmentedControl({
    required ColorScheme colorScheme,
    required String value,
    required List<String> options,
    required List<String> labels,
    required ValueChanged<String> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: options.asMap().entries.map((entry) {
          final isSelected = value == entry.value;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(entry.value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: isSelected ? colorScheme.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  labels[entry.key],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: isSelected ? colorScheme.onPrimary : colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildAccountPage(ColorScheme colorScheme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPageHeader(
            colorScheme,
            'Community Account',
            'Connect with birders',
            Icons.people_outline,
          ),
          const SizedBox(height: 32),

          if (_authSuccess) ...[
            _buildSuccessCard(colorScheme),
          ] else ...[
            // Toggle login/signup
            _buildSegmentedControl(
              colorScheme: colorScheme,
              value: _isLogin ? 'login' : 'signup',
              options: const ['login', 'signup'],
              labels: const ['Sign In', 'Create Account'],
              onChanged: (v) {
                _haptic();
                setState(() => _isLogin = v == 'login');
              },
            ),
            const SizedBox(height: 24),

            // Email field
            _buildTextField(
              colorScheme: colorScheme,
              controller: _emailController,
              label: 'Email',
              icon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 16),

            // Password field
            _buildTextField(
              colorScheme: colorScheme,
              controller: _passwordController,
              label: 'Password',
              icon: Icons.lock_outlined,
              obscureText: true,
            ),
            const SizedBox(height: 24),

            if (_authError != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: colorScheme.error, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _authError!,
                        style: TextStyle(color: colorScheme.onErrorContainer),
                      ),
                    ),
                  ],
                ),
              ),

            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                onPressed: _authLoading ? null : _handleAuth,
                child: _authLoading
                    ? SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colorScheme.onPrimary,
                  ),
                )
                    : Text(
                  _isLogin ? 'Sign In' : 'Create Account',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(height: 16),

            Center(
              child: TextButton(
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Skip Account Setup?'),
                      content: const Text(
                        'Without an account, you won\'t be able to:\n\n'
                        '- Set up your Ornimetrics OS feeder\n'
                        '- Sync bird detections to the cloud\n'
                        '- Access your data across devices\n\n'
                        'You can create an account later in Settings.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Go Back'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Skip Anyway'),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true) {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool('account_skipped', true);
                    _nextPage();
                  }
                },
                child: Text(
                  'Skip for now',
                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTextField({
    required ColorScheme colorScheme,
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    bool obscureText = false,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest.withOpacity(0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colorScheme.outline.withOpacity(0.2)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
      ),
    );
  }

  Widget _buildSuccessCard(ColorScheme colorScheme) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 600),
      curve: Curves.elasticOut,
      builder: (_, value, child) => Transform.scale(
        scale: value,
        child: child,
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.green.withOpacity(0.15),
              Colors.green.withOpacity(0.05),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.green.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_rounded, color: Colors.green, size: 48),
            ),
            const SizedBox(height: 20),
            Text(
              'Welcome aboard!',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              FirebaseAuth.instance.currentUser?.email ?? '',
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDonePage(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Animated checkmark
          AnimatedBuilder(
            animation: _breathingController,
            builder: (context, child) {
              return Transform.scale(
                scale: 1 + (_breathingController.value * 0.05),
                child: child,
              );
            },
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 800),
              curve: Curves.elasticOut,
              builder: (_, value, child) => Transform.scale(
                scale: value,
                child: child,
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Animated rings
                  ...List.generate(3, (i) {
                    return AnimatedBuilder(
                      animation: _breathingController,
                      builder: (context, _) {
                        return Container(
                          width: 140 + (i * 30) + (_breathingController.value * 20),
                          height: 140 + (i * 30) + (_breathingController.value * 20),
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
                    padding: const EdgeInsets.all(28),
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
                      Icons.check_rounded,
                      size: 60,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 48),

          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOut,
            builder: (_, value, child) => Opacity(
              opacity: value,
              child: Transform.translate(
                offset: Offset(0, 20 * (1 - value)),
                child: child,
              ),
            ),
            child: Text(
              "You're All Set!",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Your personalized bird tracking\nexperience awaits.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 40),

          // Summary cards
          _buildSummaryCard(colorScheme),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(ColorScheme colorScheme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colorScheme.outline.withOpacity(0.1)),
      ),
      child: Column(
        children: [
          _buildSummaryRow(colorScheme, Icons.palette, 'Theme', _darkMode ? 'Dark' : 'Light'),
          Divider(height: 24, color: colorScheme.outline.withOpacity(0.1)),
          _buildSummaryRow(colorScheme, Icons.vibration, 'Haptics', _hapticsEnabled ? 'On' : 'Off'),
          Divider(height: 24, color: colorScheme.outline.withOpacity(0.1)),
          _buildSummaryRow(
            colorScheme,
            Icons.person,
            'Account',
            _authSuccess ? 'Connected' : 'Guest',
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(ColorScheme colorScheme, IconData icon, String label, String value) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: colorScheme.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: colorScheme.primary, size: 18),
        ),
        const SizedBox(width: 12),
        Text(
          label,
          style: TextStyle(color: colorScheme.onSurfaceVariant),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface,
          ),
        ),
      ],
    );
  }
}