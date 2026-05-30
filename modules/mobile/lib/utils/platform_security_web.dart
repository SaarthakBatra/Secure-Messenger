class PlatformSecurityService {
  static Future<void> updateNativeSecurity(bool isVaultActive) async {
    // For Web, we can't use native window managers.
    // DOM blurring is handled purely by Flutter's UI stack (black overlay on inactive state).
  }
}
