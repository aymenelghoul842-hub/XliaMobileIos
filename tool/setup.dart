// Run AFTER `flutter create .`:   dart run tool/setup.dart
// Patches Android + iOS: plain http:// servers work, and the app is named XLiaMobile.
import 'dart:io';

void main() {
  final manifest = File('android/app/src/main/AndroidManifest.xml');
  if (manifest.existsSync()) {
    var s = manifest.readAsStringSync();
    if (!s.contains('android.permission.INTERNET')) {
      s = s.replaceFirst('<application',
          '<uses-permission android:name="android.permission.INTERNET"/>\n    <application');
    }
    if (!s.contains('usesCleartextTraffic')) {
      s = s.replaceFirst(
          '<application', '<application android:usesCleartextTraffic="true"');
    }
    // app name shown under the launcher icon
    s = s.replaceFirst(RegExp(r'android:label="[^"]*"'), 'android:label="XLiaMobile"');
    manifest.writeAsStringSync(s);
    stdout.writeln('✅ Android manifest patched');
  } else {
    stdout.writeln('⚠️  android/ not found - run "flutter create ." first');
  }

  final plist = File('ios/Runner/Info.plist');
  if (plist.existsSync()) {
    var s = plist.readAsStringSync();
    for (final key in ['CFBundleDisplayName', 'CFBundleName']) {
      s = s.replaceFirstMapped(
          RegExp('(<key>$key</key>\\s*<string>)[^<]*(</string>)'),
          (m) => '${m[1]}XLiaMobile${m[2]}');
    }
    if (!s.contains('NSAppTransportSecurity')) {
      s = s.replaceFirst('</dict>',
          '\t<key>NSAppTransportSecurity</key>\n\t<dict>\n\t\t<key>NSAllowsArbitraryLoads</key>\n\t\t<true/>\n\t</dict>\n</dict>');
    }
    plist.writeAsStringSync(s);
    stdout.writeln('✅ iOS Info.plist patched');
  }
}
