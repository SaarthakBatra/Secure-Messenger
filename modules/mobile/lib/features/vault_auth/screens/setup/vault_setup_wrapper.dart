import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/setup_wizard_provider.dart';
// ignore: avoid_relative_lib_imports
import '../../../../app/router/app_router.dart';
import 'package:go_router/go_router.dart';

class VaultSetupWrapper extends ConsumerWidget {
  const VaultSetupWrapper({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(setupWizardProvider);
    final notifier = ref.read(setupWizardProvider.notifier);

    Widget currentScreen;
    switch (state.currentStep) {
      case 0:
        currentScreen = _IntroScreen(notifier: notifier);
        break;
      case 1:
        currentScreen = _UserIdScreen(notifier: notifier);
        break;
      case 2:
        currentScreen = _RecoveryPhraseScreen(state: state, notifier: notifier);
        break;
      case 3:
        currentScreen = _VaultPinScreen(state: state, notifier: notifier);
        break;
      case 4:
        currentScreen = _DuressPinScreen(state: state, notifier: notifier);
        break;
      case 5:
        currentScreen = _GracePeriodScreen(state: state, notifier: notifier);
        break;
      case 6:
        currentScreen = _ScreenshotProtectionScreen(state: state, notifier: notifier);
        break;
      case 7:
        currentScreen = _CompletionScreen(state: state, notifier: notifier);
        break;
      default:
        currentScreen = const SizedBox();
    }

    return Theme(
      data: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F2027),
        primaryColor: const Color(0xFF00E676),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E676),
          secondary: Color(0xFF00E676),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF00E676),
            foregroundColor: const Color(0xFF0F2027),
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
      ),
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
            onPressed: () {
              context.go('/home');
            },
          ),
          title: Text('Setup - Step ${state.currentStep + 1}/8', style: const TextStyle(color: Colors.white70, fontSize: 16)),
          centerTitle: true,
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (state.error != null)
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
                    ),
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline_rounded, color: Colors.redAccent),
                        const SizedBox(width: 8),
                        Expanded(child: Text(state.error!, style: const TextStyle(color: Colors.redAccent))),
                      ],
                    ),
                  ),
                Expanded(child: currentScreen),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _IntroScreen extends StatelessWidget {
  final SetupWizardNotifier notifier;
  const _IntroScreen({required this.notifier});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.security_rounded, size: 80, color: Color(0xFF00E676)),
        const SizedBox(height: 24),
        const Text('Secure Vault', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white), textAlign: TextAlign.center),
        const SizedBox(height: 16),
        Text('Configure your hidden enclave.\nThis setup is extremely sensitive.', style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 16, height: 1.5), textAlign: TextAlign.center),
        const Spacer(),
        ElevatedButton(onPressed: notifier.nextStep, child: const Text('Start Setup')),
      ],
    );
  }
}

class _UserIdScreen extends StatelessWidget {
  final SetupWizardNotifier notifier;
  const _UserIdScreen({required this.notifier});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Secure Identity', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white), textAlign: TextAlign.center),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: const Column(
            children: [
              Icon(Icons.fingerprint_rounded, size: 48, color: Color(0xFF00E676)),
              SizedBox(height: 16),
              Text('Your User ID is cryptographic and will be securely generated by the server at the end of this wizard.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, height: 1.5)),
            ],
          ),
        ),
        const Spacer(),
        ElevatedButton(onPressed: notifier.nextStep, child: const Text('Next')),
      ],
    );
  }
}

class _RecoveryPhraseScreen extends StatelessWidget {
  final SetupWizardState state;
  final SetupWizardNotifier notifier;
  const _RecoveryPhraseScreen({required this.state, required this.notifier});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Recovery Phrase', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white), textAlign: TextAlign.center),
        const SizedBox(height: 16),
        const Text('Store this safely offline. It is the ONLY way to recover your vault.', textAlign: TextAlign.center, style: TextStyle(color: Colors.redAccent)),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.3),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF00E676).withOpacity(0.5)),
          ),
          child: Text(state.recoveryPhrase, style: const TextStyle(fontSize: 20, letterSpacing: 1.5, height: 1.6, color: Color(0xFF00E676), fontWeight: FontWeight.w600), textAlign: TextAlign.center),
        ),
        const SizedBox(height: 16),
        TextButton.icon(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: state.recoveryPhrase));
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Copied to clipboard', style: TextStyle(color: Color(0xFF0F2027))),
              backgroundColor: Color(0xFF00E676),
              behavior: SnackBarBehavior.floating,
              margin: EdgeInsets.only(bottom: 80, left: 24, right: 24),
              duration: Duration(seconds: 2),
            ));
          },
          icon: const Icon(Icons.copy_rounded, color: Colors.white70),
          label: const Text('Copy to Clipboard', style: TextStyle(color: Colors.white70)),
        ),
        const Spacer(),
        ElevatedButton(onPressed: notifier.nextStep, child: const Text('I have saved it safely')),
      ],
    );
  }
}

class _VaultPinScreen extends StatelessWidget {
  final SetupWizardState state;
  final SetupWizardNotifier notifier;
  const _VaultPinScreen({required this.state, required this.notifier});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Set Vault PIN', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white), textAlign: TextAlign.center),
        const SizedBox(height: 12),
        const Text('This unlocks your real vault. Keep it secret.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white70)),
        const SizedBox(height: 32),
        TextField(
          maxLength: 6,
          keyboardType: TextInputType.number,
          obscureText: false,
          onChanged: notifier.setVaultPin,
          style: const TextStyle(fontSize: 24, letterSpacing: 8, color: Colors.white),
          textAlign: TextAlign.center,
          decoration: InputDecoration(
            counterText: '',
            hintText: '000000',
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.2)),
            filled: true,
            fillColor: Colors.black.withOpacity(0.2),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
          ),
        ),
        const Spacer(),
        ElevatedButton(
          onPressed: state.vaultPin.length == 6 ? notifier.nextStep : null,
          child: const Text('Next'),
        ),
      ],
    );
  }
}

class _DuressPinScreen extends StatelessWidget {
  final SetupWizardState state;
  final SetupWizardNotifier notifier;
  const _DuressPinScreen({required this.state, required this.notifier});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Set Duress PIN', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white), textAlign: TextAlign.center),
        const SizedBox(height: 12),
        const Text('Entering this PIN under threat will wipe your vault or show decoy data.', textAlign: TextAlign.center, style: TextStyle(color: Colors.redAccent)),
        const SizedBox(height: 32),
        TextField(
          maxLength: 6,
          keyboardType: TextInputType.number,
          obscureText: false,
          onChanged: notifier.setDuressPin,
          style: const TextStyle(fontSize: 24, letterSpacing: 8, color: Colors.white),
          textAlign: TextAlign.center,
          decoration: InputDecoration(
            counterText: '',
            hintText: '000000',
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.2)),
            filled: true,
            fillColor: Colors.black.withOpacity(0.2),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
          ),
        ),
        const Spacer(),
        ElevatedButton(
          onPressed: state.duressPin.length == 6 ? notifier.nextStep : null,
          child: const Text('Next'),
        ),
      ],
    );
  }
}

class _GracePeriodScreen extends StatelessWidget {
  final SetupWizardState state;
  final SetupWizardNotifier notifier;
  const _GracePeriodScreen({required this.state, required this.notifier});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Lockout Delay', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white), textAlign: TextAlign.center),
        const SizedBox(height: 12),
        const Text('How long should the vault wait before auto-locking after you leave the app?', textAlign: TextAlign.center, style: TextStyle(color: Colors.white70)),
        const SizedBox(height: 32),
        SizedBox(
          height: 200,
          child: CupertinoPicker(
            itemExtent: 50,
            scrollController: FixedExtentScrollController(initialItem: state.gracePeriod ~/ 10),
            onSelectedItemChanged: (index) {
              notifier.setGracePeriod(index * 10);
            },
            children: List<Widget>.generate(31, (index) {
              final seconds = index * 10;
              return Center(
                child: Text(
                  seconds == 0 ? 'Immediately (0s)' : '$seconds seconds',
                  style: const TextStyle(color: Color(0xFF00E676), fontSize: 20, fontWeight: FontWeight.w600),
                ),
              );
            }),
          ),
        ),
        const Spacer(),
        ElevatedButton(onPressed: notifier.nextStep, child: const Text('Next')),
      ],
    );
  }
}

class _ScreenshotProtectionScreen extends StatelessWidget {
  final SetupWizardState state;
  final SetupWizardNotifier notifier;
  const _ScreenshotProtectionScreen({required this.state, required this.notifier});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Screenshot Protection', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white), textAlign: TextAlign.center),
        const SizedBox(height: 12),
        const Text('Prevent the OS from taking screenshots or showing the app in the recent task switcher.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white70)),
        const SizedBox(height: 32),
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(16),
          ),
          child: SwitchListTile(
            title: const Text('Enable Protection', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            activeColor: const Color(0xFF00E676),
            value: state.screenshotProtection,
            onChanged: notifier.setScreenshotProtection,
          ),
        ),
        const Spacer(),
        ElevatedButton(onPressed: notifier.nextStep, child: const Text('Next')),
      ],
    );
  }
}

class _CompletionScreen extends ConsumerWidget {
  final SetupWizardState state;
  final SetupWizardNotifier notifier;
  const _CompletionScreen({required this.state, required this.notifier});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.check_circle_outline_rounded, size: 80, color: Color(0xFF00E676)),
        const SizedBox(height: 24),
        const Text('Ready to Secure', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white), textAlign: TextAlign.center),
        const SizedBox(height: 16),
        if (state.userId != null)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF00E676).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF00E676).withOpacity(0.3)),
            ),
            child: Column(
              children: [
                const Text('User ID Generated', style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(state.userId!, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF00E676)), textAlign: TextAlign.center),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.copy_rounded, color: Color(0xFF00E676)),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: state.userId!));
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('Copied to clipboard', style: TextStyle(color: Color(0xFF0F2027))),
                          backgroundColor: Color(0xFF00E676),
                          behavior: SnackBarBehavior.floating,
                          margin: EdgeInsets.only(bottom: 80, left: 24, right: 24),
                          duration: Duration(seconds: 2),
                        ));
                      },
                    ),
                  ],
                ),
              ],
            ),
          )
        else
          const Text('Your cryptographic keys and settings are ready to be registered with the server.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, height: 1.5)),
        const Spacer(),
        if (state.isRegistering)
          const Center(child: CircularProgressIndicator(color: Color(0xFF00E676)))
        else
          ElevatedButton(
            onPressed: () async {
              if (state.userId == null) {
                await notifier.completeRegistration();
              } else {
                ref.read(vaultConfiguredProvider.notifier).state = true;
                context.go('/home');
              }
            },
            child: Text(state.userId == null ? 'Register Identity' : 'Exit to Decoy App'),
          ),
      ],
    );
  }
}
