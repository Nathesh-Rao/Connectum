import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../log/app_log.dart';

/// Opens an address in the phone's own browser or mail, phone and message
/// apps. `canLaunchUrl` is not used (it needs manifest queries on Android 11+):
/// the launch itself is tried and its failure reported.
class LinkLauncher {
  const LinkLauncher({this.launch = _launch});

  final Future<bool> Function(Uri uri) launch;

  static Future<bool> _launch(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);

  /// True when the phone took the address.
  Future<bool> openExternal(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return false;
    try {
      return await launch(uri);
    } on PlatformException catch (e) {
      AppLog.w('link_launcher', 'launch ${e.code}');
      return false;
    } catch (e, st) {
      AppLog.e('link_launcher', e, st);
      return false;
    }
  }
}
