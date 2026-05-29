import 'package:flutter_riverpod/flutter_riverpod.dart';

// Atomic state provider to capture error reference codes and descriptions submitted by the user
// in order to bridge the decoy module and the secure vault chat login flow.
final issueReportProvider = StateProvider<({String code, String body})>((ref) => (code: '', body: ''));

enum StealthLoginState { idle, authenticating, success, failure }

final stealthLoginStateProvider = StateProvider<StealthLoginState>((ref) => StealthLoginState.idle);

