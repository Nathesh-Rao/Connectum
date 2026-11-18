import 'crash_service.dart';

/// Every breadcrumb the app can leave. Free text is not accepted.
enum Crumb {
  screen('screen'),
  tab('tab'),
  command('cmd'),
  lifecycle('app'),
  wsConnected('ws_connected'),
  wsClosed('ws_closed'),
  wsReconnect('ws_reconnect'),
  smartviewOpen('smartview_open'),
  smartviewModeCards('smartview_mode_cards'),
  smartviewModeTable('smartview_mode_table'),
  smartviewFilterApplied('smartview_filter_applied'),
  filePreview('file_preview'),
  signIn('sign_in'),
  signOut('sign_out'),
  orgSwitched('org_switched');

  const Crumb(this.text);

  final String text;
}

class CrashBreadcrumbs {
  CrashBreadcrumbs._();

  static const maxLength = 100;
  static const maxCode = 24;

  /// `<crumb>` or `<crumb>:<code>`; the code is lower-cased, limited to
  /// a-z 0-9 _ - and cut to 24 characters.
  static String format(Crumb crumb, {String? code}) {
    final clean = (code ?? '').toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9_-]'),
      '_',
    );
    final cut = clean.length > maxCode ? clean.substring(0, maxCode) : clean;
    final text = cut.isEmpty ? crumb.text : '${crumb.text}:$cut';
    return text.length > maxLength ? text.substring(0, maxLength) : text;
  }

  static void add(Crumb crumb, {String? code}) =>
      CrashService.current.addCrumb(format(crumb, code: code));
}
