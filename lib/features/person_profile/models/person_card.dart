/// What the app already holds about one person; every field but the username
/// can be empty and an empty one shows nothing.
class PersonCard {
  const PersonCard({
    required this.username,
    this.name = '',
    this.designation = '',
    this.department = '',
    this.branch = '',
    this.email = '',
    this.mobile = '',
  });

  final String username;
  final String name;
  final String designation;
  final String department;
  final String branch;
  final String email;
  final String mobile;

  String get displayName => name.isNotEmpty ? name : username;

  /// Department and branch together ("Sales • Pune"), or whichever exists.
  String get workplace =>
      [department, branch].where((t) => t.isNotEmpty).join(' • ');

  bool get hasContact => email.isNotEmpty || mobile.isNotEmpty;
}
