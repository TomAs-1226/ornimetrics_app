import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Access the global notifiers from main
import '../main.dart';

class OnboardingScreen extends StatefulWidget {
  final VoidCallback onComplete;

  const OnboardingScreen({super.key, required this.onComplete});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  // Settings state
  bool _darkMode = false;
  Color _selectedColor = Colors.green;
  bool _hapticsEnabled = true;
  bool _autoRefresh = false;
  double _refreshInterval = 60.0;

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
  ];

  @override
  void initState() {
    super.initState();
    _loadCurrentSettings();
  }

  Future<void> _loadCurrentSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _darkMode = prefs.getBool('pref_dark_mode') ?? false;
      _hapticsEnabled = prefs.getBool('pref_haptics_enabled') ?? true;
      _autoRefresh = prefs.getBool('pref_auto_refresh_enabled') ?? false;
      _refreshInterval = prefs.getDouble('pref_auto_refresh_interval') ?? 60.0;
      final seedValue = prefs.getInt('pref_seed_color');
      if (seedValue != null) {
        _selectedColor = Color(seedValue);
      }
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('pref_dark_mode', _darkMode);
    await prefs.setBool('pref_haptics_enabled', _hapticsEnabled);
    await prefs.setBool('pref_auto_refresh_enabled', _autoRefresh);
    await prefs.setDouble('pref_auto_refresh_interval', _refreshInterval);
    await prefs.setInt('pref_seed_color', _selectedColor.value);

    // Update global notifiers
    themeNotifier.value = _darkMode ? ThemeMode.dark : ThemeMode.light;
    hapticsEnabledNotifier.value = _hapticsEnabled;
    seedColorNotifier.value = _selectedColor;
    autoRefreshEnabledNotifier.value = _autoRefresh;
    autoRefreshIntervalNotifier.value = _refreshInterval;
  }

  void _nextPage() {
    _haptic();
    if (_currentPage < 4) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 400),
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
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  void _haptic() {
    if (_hapticsEnabled && Platform.isIOS) {
      HapticFeedback.lightImpact();
    }
  }

  Future<void> _completeOnboarding() async {
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _selectedColor,
      brightness: _darkMode ? Brightness.dark : Brightness.light,
    );

    return Theme(
      data: theme.copyWith(colorScheme: colorScheme),
      child: Scaffold(
        backgroundColor: colorScheme.surface,
        body: SafeArea(
          child: Column(
            children: [
              // Progress indicator
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: List.generate(5, (i) {
                    return Expanded(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        height: 4,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          color: i <= _currentPage
                              ? colorScheme.primary
                              : colorScheme.primary.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(2),
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
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    if (_currentPage > 0)
                      TextButton.icon(
                        onPressed: _previousPage,
                        icon: const Icon(Icons.arrow_back_rounded),
                        label: const Text('Back'),
                      )
                    else
                      const SizedBox(width: 100),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: _nextPage,
                      icon: Icon(_currentPage == 4
                          ? Icons.check_rounded
                          : Icons.arrow_forward_rounded),
                      label: Text(_currentPage == 4 ? 'Get Started' : 'Next'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWelcomePage(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 800),
            curve: Curves.elasticOut,
            builder: (_, value, child) => Transform.scale(
              scale: value,
              child: child,
            ),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.flutter_dash,
                size: 80,
                color: colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(height: 40),
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
              'Welcome to\nOrnimetrics',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
                height: 1.2,
              ),
            ),
          ),
          const SizedBox(height: 16),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 600),
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
              ),
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
          Text(
            'Customize Your Theme',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Choose colors and appearance',
            style: TextStyle(
              fontSize: 16,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 32),

          // Dark mode toggle
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Icon(
                  _darkMode ? Icons.dark_mode : Icons.light_mode,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Dark Mode',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      Text(
                        _darkMode ? 'Enabled' : 'Disabled',
                        style: TextStyle(
                          fontSize: 14,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: _darkMode,
                  onChanged: (v) {
                    _haptic();
                    setState(() => _darkMode = v);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Color picker
          Text(
            'Accent Color',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: _colorOptions.map((color) {
              final isSelected = _selectedColor.value == color.value;
              return GestureDetector(
                onTap: () {
                  _haptic();
                  setState(() => _selectedColor = color);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? colorScheme.onSurface : Colors.transparent,
                      width: 3,
                    ),
                    boxShadow: isSelected
                        ? [BoxShadow(color: color.withOpacity(0.4), blurRadius: 12, spreadRadius: 2)]
                        : null,
                  ),
                  child: isSelected
                      ? const Icon(Icons.check, color: Colors.white, size: 28)
                      : null,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 32),

          // Preview card
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.palette, color: colorScheme.primary),
                    const SizedBox(width: 12),
                    Text(
                      'Preview',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'This is how your app will look with the selected theme.',
                  style: TextStyle(
                    color: colorScheme.onPrimaryContainer.withOpacity(0.8),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    FilledButton(
                      onPressed: () {},
                      child: const Text('Button'),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton(
                      onPressed: () {},
                      child: const Text('Outlined'),
                    ),
                  ],
                ),
              ],
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
          Text(
            'App Settings',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Configure how the app behaves',
            style: TextStyle(
              fontSize: 16,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 32),

          // Haptics toggle
          _buildSettingTile(
            colorScheme: colorScheme,
            icon: Icons.vibration,
            title: 'Haptic Feedback',
            subtitle: 'Feel subtle vibrations on interactions',
            value: _hapticsEnabled,
            onChanged: (v) {
              if (v) _haptic();
              setState(() => _hapticsEnabled = v);
            },
          ),
          const SizedBox(height: 16),

          // Auto refresh toggle
          _buildSettingTile(
            colorScheme: colorScheme,
            icon: Icons.refresh,
            title: 'Auto Refresh Data',
            subtitle: 'Automatically update detection data',
            value: _autoRefresh,
            onChanged: (v) {
              _haptic();
              setState(() => _autoRefresh = v);
            },
          ),

          if (_autoRefresh) ...[
            const SizedBox(height: 16),
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Refresh Interval',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${_refreshInterval.round()} seconds',
                    style: TextStyle(
                      fontSize: 14,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Slider(
                    value: _refreshInterval,
                    min: 30,
                    max: 300,
                    divisions: 9,
                    label: '${_refreshInterval.round()}s',
                    onChanged: (v) {
                      setState(() => _refreshInterval = v);
                    },
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSettingTile({
    required ColorScheme colorScheme,
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, color: colorScheme.primary),
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
                    fontSize: 14,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildAccountPage(ColorScheme colorScheme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Community Account',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Sign in to share sightings and connect with birders',
            style: TextStyle(
              fontSize: 16,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 32),

          if (_authSuccess) ...[
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.green.withOpacity(0.3)),
              ),
              child: Column(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    'Successfully signed in!',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
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
          ] else ...[
            // Toggle login/signup
            Container(
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        _haptic();
                        setState(() => _isLogin = true);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: _isLogin ? colorScheme.primary : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'Sign In',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: _isLogin ? colorScheme.onPrimary : colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        _haptic();
                        setState(() => _isLogin = false);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: !_isLogin ? colorScheme.primary : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'Sign Up',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: !_isLogin ? colorScheme.onPrimary : colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Email field
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: 'Email',
                prefixIcon: const Icon(Icons.email_outlined),
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Password field
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.lock_outlined),
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 24),

            if (_authError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  _authError!,
                  style: TextStyle(color: colorScheme.error),
                ),
              ),

            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _authLoading ? null : _handleAuth,
                child: _authLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(_isLogin ? 'Sign In' : 'Create Account'),
              ),
            ),
            const SizedBox(height: 16),

            Center(
              child: TextButton(
                onPressed: _nextPage,
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

  Widget _buildDonePage(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 800),
            curve: Curves.elasticOut,
            builder: (_, value, child) => Transform.scale(
              scale: value,
              child: child,
            ),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_rounded,
                size: 80,
                color: Colors.green,
              ),
            ),
          ),
          const SizedBox(height: 40),
          Text(
            "You're All Set!",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Start tracking bird detections\nand exploring your data.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 48),

          // Summary
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                _buildSummaryRow(
                  colorScheme,
                  Icons.palette,
                  'Theme',
                  _darkMode ? 'Dark' : 'Light',
                ),
                const Divider(height: 24),
                _buildSummaryRow(
                  colorScheme,
                  Icons.vibration,
                  'Haptics',
                  _hapticsEnabled ? 'Enabled' : 'Disabled',
                ),
                const Divider(height: 24),
                _buildSummaryRow(
                  colorScheme,
                  Icons.person,
                  'Account',
                  _authSuccess
                      ? 'Signed in'
                      : 'Not signed in',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(ColorScheme colorScheme, IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: colorScheme.primary, size: 20),
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
