import 'dart:io';

String? getProfile() {
  const dartProfile = String.fromEnvironment('APP_PROFILE');
  if (dartProfile.isNotEmpty) return dartProfile;
  const dartMProfile = String.fromEnvironment('MULTILINGO_PROFILE');
  if (dartMProfile.isNotEmpty) return dartMProfile;
  try {
    final envProfile = Platform.environment['APP_PROFILE'];
    if (envProfile != null && envProfile.isNotEmpty) return envProfile;
    final envMProfile = Platform.environment['MULTILINGO_PROFILE'];
    if (envMProfile != null && envMProfile.isNotEmpty) return envMProfile;
  } catch (_) {
    // Platform.environment can throw in some environments/test harnesses
  }
  return null;
}
