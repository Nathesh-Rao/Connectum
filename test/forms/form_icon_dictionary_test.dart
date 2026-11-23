import 'package:connectum/features/forms/form_icon_dictionary.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const themes = <String, IconData>{
    'Leave request': Icons.beach_access_outlined,
    'Vacation': Icons.beach_access_outlined,
    'Time off': Icons.beach_access_outlined,
    'Punch In': Icons.login,
    'Punch Out': Icons.logout,
    'Attendance': Icons.event_available_outlined,
    'Regularize': Icons.event_available_outlined,
    'Regularise day': Icons.event_available_outlined,
    'Task': Icons.task_alt_outlined,
    'Todo': Icons.task_alt_outlined,
    'Ticket': Icons.support_agent_outlined,
    'Support': Icons.support_agent_outlined,
    'Issue': Icons.support_agent_outlined,
    'Complaint': Icons.support_agent_outlined,
    'Time sheet': Icons.schedule_outlined,
    'Timesheet': Icons.schedule_outlined,
    'Hours': Icons.schedule_outlined,
    'Expense': Icons.receipt_long_outlined,
    'Claim': Icons.receipt_long_outlined,
    'Reimbursement': Icons.receipt_long_outlined,
    'Travel': Icons.flight_takeoff_outlined,
    'Trip': Icons.flight_takeoff_outlined,
    'Visit': Icons.flight_takeoff_outlined,
    'Vendor': Icons.storefront_outlined,
    'Supplier': Icons.storefront_outlined,
    'Invoice': Icons.payments_outlined,
    'Bill': Icons.payments_outlined,
    'Payment': Icons.payments_outlined,
    'Payroll': Icons.payments_outlined,
    'Salary': Icons.payments_outlined,
    'Purchase': Icons.shopping_cart_outlined,
    'PO': Icons.shopping_cart_outlined,
    'Order': Icons.shopping_cart_outlined,
    'Requisition': Icons.shopping_cart_outlined,
    'Inventory': Icons.inventory_2_outlined,
    'Stock': Icons.inventory_2_outlined,
    'Asset': Icons.inventory_2_outlined,
    'Delivery': Icons.local_shipping_outlined,
    'Shipment': Icons.local_shipping_outlined,
    'Dispatch': Icons.local_shipping_outlined,
    'Quality': Icons.fact_check_outlined,
    'Inspection': Icons.fact_check_outlined,
    'Audit': Icons.fact_check_outlined,
    'Checklist': Icons.fact_check_outlined,
    'Safety': Icons.health_and_safety_outlined,
    'Incident': Icons.health_and_safety_outlined,
    'Accident': Icons.health_and_safety_outlined,
    'Maintenance': Icons.build_outlined,
    'Repair': Icons.build_outlined,
    'Service request': Icons.build_outlined,
    'Feedback': Icons.rate_review_outlined,
    'Survey': Icons.rate_review_outlined,
    'Review': Icons.rate_review_outlined,
    'Rating': Icons.rate_review_outlined,
    'Onboarding': Icons.person_add_alt_outlined,
    'Joining': Icons.person_add_alt_outlined,
    'Hiring': Icons.person_add_alt_outlined,
    'Recruitment': Icons.person_add_alt_outlined,
    'Interview': Icons.person_add_alt_outlined,
    'Resignation': Icons.exit_to_app,
    'Exit': Icons.exit_to_app,
    'Training': Icons.school_outlined,
    'Learning': Icons.school_outlined,
    'Meeting': Icons.event_outlined,
    'Appointment': Icons.event_outlined,
    'Booking': Icons.event_outlined,
    'Approval': Icons.approval_outlined,
    'Request': Icons.approval_outlined,
    'Report': Icons.assessment_outlined,
    'Customer': Icons.groups_outlined,
    'Lead': Icons.groups_outlined,
    'Sales': Icons.groups_outlined,
    'Project': Icons.account_tree_outlined,
    'Document': Icons.article_outlined,
    'Contract': Icons.article_outlined,
    'Agreement': Icons.article_outlined,
    'Leave balance': Icons.account_balance_wallet_outlined,
    'WFH': Icons.home_work_outlined,
    'Work from home': Icons.home_work_outlined,
    'Overtime': Icons.more_time_outlined,
    'Transfer': Icons.swap_horiz,
    'Loan': Icons.savings_outlined,
    'Advance': Icons.savings_outlined,
  };

  test('every theme maps to its icon', () {
    themes.forEach((label, icon) {
      expect(FormIconDictionary.pick(label), icon, reason: label);
    });
  });

  test('case-insensitive', () {
    expect(
      FormIconDictionary.pick('LEAVE REQUEST'),
      Icons.beach_access_outlined,
    );
    expect(FormIconDictionary.pick('eXpEnSe'), Icons.receipt_long_outlined);
  });

  test('stems and plurals', () {
    expect(FormIconDictionary.pick('Leaves'), Icons.beach_access_outlined);
    expect(FormIconDictionary.pick('Expenses'), Icons.receipt_long_outlined);
    expect(
      FormIconDictionary.pick('Purchase orders'),
      Icons.shopping_cart_outlined,
    );
  });

  test('whole words only for short keywords', () {
    expect(FormIconDictionary.pick('Pole'), isNull);
    expect(FormIconDictionary.pick('Bottle'), isNull);
  });

  test('no match falls back to the default', () {
    expect(FormIconDictionary.pick('Zzz'), isNull);
    expect(
      FormIconDictionary.resolve('Zzz', fallback: Icons.description_outlined),
      Icons.description_outlined,
    );
  });

  test('specific rules come before general ones', () {
    expect(
      FormIconDictionary.pick('Leave balance'),
      Icons.account_balance_wallet_outlined,
    );
    expect(FormIconDictionary.pick('Leave'), Icons.beach_access_outlined);
    expect(
      FormIconDictionary.pick('Work from home request'),
      Icons.home_work_outlined,
    );
  });

  test('explicit icon wins', () {
    expect(
      FormIconDictionary.resolve(
        'Leave',
        explicit: Icons.bolt,
        fallback: Icons.description_outlined,
      ),
      Icons.bolt,
    );
  });
}
