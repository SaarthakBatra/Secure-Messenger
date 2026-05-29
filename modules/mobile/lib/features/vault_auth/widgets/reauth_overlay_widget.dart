import 'dart:async';
import 'dart:ui';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Removed shared_preferences
import '../../../app/router/app_router.dart';
import '../../security/services/sodium_crypto_service.dart';

class ReauthOverlayWidget extends ConsumerStatefulWidget {
  final Completer<bool> completer;

  const ReauthOverlayWidget({super.key, required this.completer});

  @override
  ConsumerState<ReauthOverlayWidget> createState() => _ReauthOverlayWidgetState();
}

class _ReauthOverlayWidgetState extends ConsumerState<ReauthOverlayWidget> with SingleTickerProviderStateMixin {
  String _pin = '';
  int _remainingSeconds = 10;
  Timer? _countdownTimer;
  bool _isLoading = false;
  bool _isError = false;
  
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  @override
  void initState() {
    super.initState();
    _remainingSeconds = ref.read(vaultSessionNotifierProvider).reauthGracePeriodSeconds;
    
    _shakeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _shakeAnimation = Tween<double>(begin: 0, end: 10).animate(CurvedAnimation(parent: _shakeController, curve: Curves.elasticIn))
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _shakeController.reset();
        }
      });
    
    _startCountdown();
  }

  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds > 0) {
        setState(() {
          _remainingSeconds--;
        });
      } else {
        timer.cancel();
        _eject();
      }
    });
  }

  void _eject() {
    if (!widget.completer.isCompleted) {
      widget.completer.complete(false);
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _shakeController.dispose();
    super.dispose();
  }

  void _onKeyPress(String digit) {
    if (_pin.length < 6 && !_isLoading) {
      setState(() {
        _pin += digit;
        _isError = false;
      });
      if (_pin.length == 6) {
        _submitPin();
      }
    }
  }

  void _onBackspace() {
    if (_pin.isNotEmpty && !_isLoading) {
      setState(() {
        _pin = _pin.substring(0, _pin.length - 1);
        _isError = false;
      });
    }
  }

  Future<void> _submitPin() async {
    setState(() => _isLoading = true);
    
    try {
      final token = ref.read(vaultSessionNotifierProvider).token;
      if (token == null) throw Exception('No active session token');
      
      final clientKey = SodiumCryptoService.generateClientKey(_pin, 'dev-fingerprint-mobile');
      
      final cleanDio = Dio(BaseOptions(baseUrl: 'http://localhost:3000'));
      final response = await cleanDio.post('/auth/reauth', data: {
        'sessionToken': token,
        'clientKey': clientKey,
      });
      
      final newToken = response.data['sessionToken'] as String;
      
      // Update session notifier
      final notifier = ref.read(vaultSessionNotifierProvider);
      notifier.setSession(notifier.sessionType, token: newToken, refreshToken: notifier.refreshToken, reauthGracePeriodSeconds: notifier.reauthGracePeriodSeconds);
      
      if (!widget.completer.isCompleted) {
        widget.completer.complete(true);
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _isError = true;
        _pin = '';
      });
      _shakeController.forward();
    }
  }

  Widget _buildKeypadButton(String label, {VoidCallback? onPressed, IconData? icon}) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Material(
          color: Colors.white.withOpacity(0.05),
          shape: const CircleBorder(),
          clipBehavior: Clip.hardEdge,
          child: InkWell(
            onTap: onPressed ?? () => _onKeyPress(label),
            child: AspectRatio(
              aspectRatio: 1,
              child: Center(
                child: icon != null 
                    ? Icon(icon, color: Colors.white, size: 28)
                    : Text(label, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w300)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  const Color(0xFF0F2027).withOpacity(0.9),
                  const Color(0xFF203A43).withOpacity(0.9),
                  const Color(0xFF2C5364).withOpacity(0.9),
                ],
              ),
            ),
            child: SafeArea(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.lock_outline_rounded, color: Colors.white54, size: 48),
                  const SizedBox(height: 24),
                  const Text('Session Expired', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Text('Verify PIN to continue ($_remainingSeconds)', style: TextStyle(color: _remainingSeconds <= 3 ? Colors.redAccent : Colors.white70, fontSize: 16)),
                  const SizedBox(height: 48),
                  
                  AnimatedBuilder(
                    animation: _shakeAnimation,
                    builder: (context, child) {
                      return Transform.translate(
                        offset: Offset(_shakeAnimation.value * (_isError ? 1 : 0), 0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(6, (index) {
                            final isFilled = index < _pin.length;
                            return Container(
                              margin: const EdgeInsets.symmetric(horizontal: 8),
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isFilled ? const Color(0xFF00E676) : Colors.white.withOpacity(0.2),
                                boxShadow: isFilled ? [
                                  BoxShadow(color: const Color(0xFF00E676).withOpacity(0.5), blurRadius: 10, spreadRadius: 2)
                                ] : [],
                              ),
                            );
                          }),
                        ),
                      );
                    }
                  ),
                  
                  const SizedBox(height: 16),
                  if (_isLoading)
                    const SizedBox(
                      height: 20, width: 20,
                      child: CircularProgressIndicator(color: Color(0xFF00E676), strokeWidth: 2),
                    )
                  else
                    const SizedBox(height: 20),
                    
                  const SizedBox(height: 48),
                  
                  // Keypad
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      children: [
                        Row(children: ['1', '2', '3'].map((l) => _buildKeypadButton(l)).toList()),
                        Row(children: ['4', '5', '6'].map((l) => _buildKeypadButton(l)).toList()),
                        Row(children: ['7', '8', '9'].map((l) => _buildKeypadButton(l)).toList()),
                        Row(
                          children: [
                            const Spacer(),
                            _buildKeypadButton('0'),
                            _buildKeypadButton('', icon: Icons.backspace_rounded, onPressed: _onBackspace),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
