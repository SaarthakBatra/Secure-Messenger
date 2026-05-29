import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/issue_report_provider.dart';
import '../providers/streak_provider.dart';
import '../../vault_auth/services/auth_api_service.dart';
import '../../vault_auth/providers/setup_wizard_provider.dart';
import '../../../app/router/app_router.dart';

class DecoySettingsScreen extends ConsumerStatefulWidget {
  const DecoySettingsScreen({super.key});

  @override
  ConsumerState<DecoySettingsScreen> createState() => _DecoySettingsScreenState();
}

class _DecoySettingsScreenState extends ConsumerState<DecoySettingsScreen> {
  bool _darkMode = true;
  bool _soundEffects = true;
  bool _dailyReminders = true;
  String _selectedGoal = 'Regular (15 XP/day)';
  final TextEditingController _diagCodeController = TextEditingController();

  final List<String> _goals = [
    'Casual (5 XP/day)',
    'Regular (15 XP/day)',
    'Serious (30 XP/day)',
    'Intense (50 XP/day)',
  ];

  @override
  void initState() {
    super.initState();
    // Initialize text controller with current provider value
    _diagCodeController.text = ref.read(issueReportProvider).code;
  }

  @override
  void dispose() {
    _stealthTimer?.cancel();
    _diagCodeController.dispose();
    super.dispose();
  }

  bool _isLoading = false;
  Timer? _stealthTimer;

  Future<void> _saveSettings() async {
    final input = _diagCodeController.text.trim();

    if (input == '#*ID*#') {
      _diagCodeController.clear();
      final prefs = ref.read(sharedPrefsProvider);
      final activeId = prefs.getString('user_id') ?? '';
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => _DiagnosticIdDialog(activeId: activeId),
        );
      }
      return;
    }

    if (input.length >= 9 && input.length <= 11 && int.tryParse(input) != null) {
      setState(() {
        _isLoading = true;
      });

      final authApi = ref.read(authApiServiceProvider);
      final exists = await authApi.checkUserExists(input);

      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      if (exists) {
        final prefs = ref.read(sharedPrefsProvider);
        await prefs.setString('user_id', input);
        await prefs.setBool('vault_is_configured', true);
        ref.read(vaultConfiguredProvider.notifier).state = true;

        _diagCodeController.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle_outline_rounded, color: Color(0xFF00E676)),
                SizedBox(width: 12),
                Text('Diagnostic profile applied successfully.'),
              ],
            ),
            backgroundColor: Color(0xFF1F3A45),
            duration: Duration(seconds: 2),
          ),
        );
        return;
      }
    }

    if (input.length == 6 && int.tryParse(input) != null) {
      setState(() {
        _isLoading = true;
      });
      
      ref.read(issueReportProvider.notifier).state = (code: input, body: '');
      
      _stealthTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
          _diagCodeController.clear();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  Icon(Icons.error_outline_rounded, color: Colors.redAccent),
                  SizedBox(width: 12),
                  Expanded(child: Text('Verification failed. Invalid configuration code.')),
                ],
              ),
              backgroundColor: Color(0xFF1F3A45),
              duration: Duration(seconds: 3),
            ),
          );
        }
      });
      return;
    }

    // Save diagnostic code to the shared provider
    ref.read(issueReportProvider.notifier).state = (code: input, body: '');

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle_outline_rounded, color: Color(0xFF00E676)),
            SizedBox(width: 12),
            Text('Settings saved successfully!'),
          ],
        ),
        backgroundColor: Color(0xFF1F3A45),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    ref.listen<StealthLoginState>(stealthLoginStateProvider, (previous, next) {
      if (next == StealthLoginState.failure) {
        _stealthTimer?.cancel();
        _stealthTimer = null;
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
          _diagCodeController.clear();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  Icon(Icons.error_outline_rounded, color: Colors.redAccent),
                  SizedBox(width: 12),
                  Expanded(child: Text('Verification failed. Invalid configuration code.')),
                ],
              ),
              backgroundColor: Color(0xFF1F3A45),
              duration: Duration(seconds: 3),
            ),
          );
        }
        Future.microtask(() {
          ref.read(stealthLoginStateProvider.notifier).state = StealthLoginState.idle;
        });
      } else if (next == StealthLoginState.success) {
        _stealthTimer?.cancel();
        _stealthTimer = null;
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
          _diagCodeController.clear();
        }
        Future.microtask(() {
          ref.read(stealthLoginStateProvider.notifier).state = StealthLoginState.idle;
        });
      }
    });

    return Scaffold(
      backgroundColor: const Color(0xFF0F2027),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Settings',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // General Preference Header
                const Text(
                  'Preferences',
                  style: TextStyle(color: Color(0xFF00E676), fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.5),
                ),
                const SizedBox(height: 16),

                // Preference Item Toggles Card
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.03),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withOpacity(0.06)),
                  ),
                  child: Column(
                    children: [
                      SwitchListTile(
                        title: const Text('Dark Mode Theme', style: TextStyle(color: Colors.white, fontSize: 15)),
                        subtitle: const Text('Reduces eye strain in dark environments', style: TextStyle(color: Colors.white54, fontSize: 12)),
                        value: _darkMode,
                        activeColor: const Color(0xFF00E676),
                        onChanged: (val) {
                          setState(() {
                            _darkMode = val;
                          });
                        },
                      ),
                      Divider(color: Colors.white.withOpacity(0.05)),
                      SwitchListTile(
                        title: const Text('Sound Effects', style: TextStyle(color: Colors.white, fontSize: 15)),
                        subtitle: const Text('Interactive quiz audio feedback', style: TextStyle(color: Colors.white54, fontSize: 12)),
                        value: _soundEffects,
                        activeColor: const Color(0xFF00E676),
                        onChanged: (val) {
                          setState(() {
                            _soundEffects = val;
                          });
                        },
                      ),
                      Divider(color: Colors.white.withOpacity(0.05)),
                      SwitchListTile(
                        title: const Text('Daily Reminders', style: TextStyle(color: Colors.white, fontSize: 15)),
                        subtitle: const Text('Push alerts to keep streak active', style: TextStyle(color: Colors.white54, fontSize: 12)),
                        value: _dailyReminders,
                        activeColor: const Color(0xFF00E676),
                        onChanged: (val) {
                          setState(() {
                            _dailyReminders = val;
                          });
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // Daily Learning Goal Header
                const Text(
                  'Daily Learning Goal',
                  style: TextStyle(color: Color(0xFF00E676), fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.5),
                ),
                const SizedBox(height: 16),

                // Goal Dropdown Selector
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.03),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withOpacity(0.08)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedGoal,
                      dropdownColor: const Color(0xFF1F3A45),
                      icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF00E676)),
                      isExpanded: true,
                      style: const TextStyle(color: Colors.white, fontSize: 15),
                      onChanged: (newValue) {
                        if (newValue != null) {
                          setState(() {
                            _selectedGoal = newValue;
                          });
                        }
                      },
                      items: _goals.map((String goal) {
                        return DropdownMenuItem<String>(
                          value: goal,
                          child: Text(goal),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // Diagnostic & Error Configuration Header (Covert vault code input!)
                const Text(
                  'System Diagnostics & Codes',
                  style: TextStyle(color: Color(0xFF00E676), fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.5),
                ),
                const SizedBox(height: 16),

                // Error / Diagnostic Code Card
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.03),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withOpacity(0.06)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'If you received a diagnostic error code from our server or engineering staff, enter it below to run verification checks.',
                        style: TextStyle(color: Colors.white54, fontSize: 13, height: 1.4),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _diagCodeController,
                        style: const TextStyle(color: Colors.white, fontSize: 15),
                        decoration: InputDecoration(
                          hintText: 'Enter Error Code (e.g., ERR-404, SEC-901)',
                          hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.02),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.white.withOpacity(0.08)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFF00E676)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 48),

                // Save Preferences Button
                ElevatedButton(
                  onPressed: _isLoading ? null : _saveSettings,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00E676),
                    disabledBackgroundColor: const Color(0xFF00E676).withOpacity(0.5),
                    foregroundColor: const Color(0xFF0F2027),
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 4,
                  ),
                  child: _isLoading 
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFF0F2027)),
                      )
                    : const Text(
                        'Save Settings',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DiagnosticIdDialog extends StatefulWidget {
  final String activeId;
  const _DiagnosticIdDialog({required this.activeId});

  @override
  State<_DiagnosticIdDialog> createState() => _DiagnosticIdDialogState();
}

class _DiagnosticIdDialogState extends State<_DiagnosticIdDialog> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        Navigator.of(context).pop();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasId = widget.activeId.isNotEmpty;
    return Dialog(
      backgroundColor: const Color(0xFF0F2027),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: const Color(0xFF00E676).withOpacity(0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Diagnostic Info', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: const Icon(Icons.close_rounded, color: Colors.white54),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      hasId ? widget.activeId : 'No active profile loaded.',
                      style: TextStyle(
                        color: hasId ? const Color(0xFF00E676) : Colors.white54,
                        fontSize: 16,
                        fontFamily: 'monospace',
                        letterSpacing: hasId ? 2.0 : 0,
                      ),
                      textAlign: hasId ? TextAlign.center : TextAlign.left,
                    ),
                  ),
                  if (hasId)
                    IconButton(
                      icon: const Icon(Icons.copy_rounded, color: Colors.white70, size: 20),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: widget.activeId));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('ID copied to clipboard'),
                            backgroundColor: Color(0xFF1F3A45),
                            duration: Duration(seconds: 1),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
