import 'package:flutter/material.dart';

class FormIconRule {
  const FormIconRule(this.keywords, this.icon);

  /// Lower-case words or phrases. A word matches a label word that equals it,
  /// or (from 4 letters) starts with it, so "leave" also finds "leaves".
  final List<String> keywords;
  final IconData icon;
}

/// Picks an icon from a form's label. First match wins, so the list runs from
/// specific to general.
class FormIconDictionary {
  FormIconDictionary._();

  static const rules = <FormIconRule>[
    FormIconRule(['leave balance'], Icons.account_balance_wallet_outlined),
    FormIconRule(['work from home', 'wfh'], Icons.home_work_outlined),
    FormIconRule(['punch in', 'check in', 'clock in'], Icons.login),
    FormIconRule(['punch out', 'check out', 'clock out'], Icons.logout),
    FormIconRule([
      'leave',
      'vacation',
      'time off',
      'holiday',
    ], Icons.beach_access_outlined),
    FormIconRule([
      'attendance',
      'regularize',
      'regularise',
      'regularization',
      'regularisation',
    ], Icons.event_available_outlined),
    FormIconRule(['overtime', 'ot'], Icons.more_time_outlined),
    FormIconRule(['time sheet', 'timesheet', 'hours'], Icons.schedule_outlined),
    FormIconRule(['task', 'todo', 'to do'], Icons.task_alt_outlined),
    FormIconRule([
      'ticket',
      'support',
      'issue',
      'complaint',
      'helpdesk',
    ], Icons.support_agent_outlined),
    FormIconRule([
      'expense',
      'claim',
      'reimbursement',
    ], Icons.receipt_long_outlined),
    FormIconRule(['loan', 'advance'], Icons.savings_outlined),
    FormIconRule([
      'invoice',
      'bill',
      'payment',
      'payroll',
      'salary',
    ], Icons.payments_outlined),
    FormIconRule(['travel', 'trip', 'visit'], Icons.flight_takeoff_outlined),
    FormIconRule(['vendor', 'supplier'], Icons.storefront_outlined),
    FormIconRule([
      'purchase',
      'po',
      'order',
      'requisition',
    ], Icons.shopping_cart_outlined),
    FormIconRule([
      'delivery',
      'shipment',
      'dispatch',
    ], Icons.local_shipping_outlined),
    FormIconRule(['inventory', 'stock', 'asset'], Icons.inventory_2_outlined),
    FormIconRule([
      'quality',
      'inspection',
      'audit',
      'checklist',
    ], Icons.fact_check_outlined),
    FormIconRule([
      'safety',
      'incident',
      'accident',
    ], Icons.health_and_safety_outlined),
    FormIconRule([
      'maintenance',
      'repair',
      'service request',
    ], Icons.build_outlined),
    FormIconRule([
      'feedback',
      'survey',
      'review',
      'rating',
    ], Icons.rate_review_outlined),
    FormIconRule(['resignation', 'exit'], Icons.exit_to_app),
    FormIconRule([
      'onboarding',
      'joining',
      'hiring',
      'recruitment',
      'interview',
    ], Icons.person_add_alt_outlined),
    FormIconRule(['training', 'learning'], Icons.school_outlined),
    FormIconRule(['meeting', 'appointment', 'booking'], Icons.event_outlined),
    FormIconRule(['transfer'], Icons.swap_horiz),
    FormIconRule(['customer', 'lead', 'sales'], Icons.groups_outlined),
    FormIconRule(['project'], Icons.account_tree_outlined),
    FormIconRule(['document', 'contract', 'agreement'], Icons.article_outlined),
    FormIconRule(['report'], Icons.assessment_outlined),
    FormIconRule(['approval', 'request'], Icons.approval_outlined),
  ];

  static List<String> _words(String text) => [
    for (final w in text.toLowerCase().split(RegExp(r'[^a-z0-9]+')))
      if (w.isNotEmpty) w,
  ];

  static bool _matches(List<String> words, String keyword) {
    final k = _words(keyword);
    for (var i = 0; i + k.length <= words.length; i++) {
      var isHit = true;
      for (var j = 0; j < k.length; j++) {
        final w = words[i + j];
        final isLast = j == k.length - 1;
        final isWord =
            w == k[j] || (isLast && k[j].length >= 4 && w.startsWith(k[j]));
        if (!isWord) {
          isHit = false;
          break;
        }
      }
      if (isHit) return true;
    }
    return false;
  }

  /// The icon for [label], or null when no rule matches.
  static IconData? pick(String label) {
    final words = _words(label);
    if (words.isEmpty) return null;
    for (final r in rules) {
      for (final k in r.keywords) {
        if (_matches(words, k)) return r.icon;
      }
    }
    return null;
  }

  /// An explicit icon wins, then the dictionary, then [fallback].
  static IconData resolve(
    String label, {
    IconData? explicit,
    required IconData fallback,
  }) => explicit ?? pick(label) ?? fallback;
}
