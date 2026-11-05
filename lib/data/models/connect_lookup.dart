import 'connect_card.dart';
import 'ids.dart';

/// The person behind a person's code (`connect.lookup` / `connect.scan`).
class ConnectPerson {
  const ConnectPerson({
    required this.name,
    required this.username,
    this.designation = '',
    this.department = '',
  });

  final String name;
  final String username;
  final String designation;
  final String department;

  /// "Designation, Department" when either is present.
  String get role =>
      [designation, department].where((s) => s.isNotEmpty).join(', ');

  factory ConnectPerson.fromJson(Map<String, dynamic> user) => ConnectPerson(
    name: idText(user['name']).isEmpty
        ? idText(user['username'])
        : idText(user['name']),
    username: idText(user['username']),
    designation: idText(user['designation']),
    department: idText(user['department']),
  );
}

/// What a code is inside the signed-in organisation: a person or the
/// organisation itself.
class ConnectLookup {
  const ConnectLookup.person(
    ConnectPerson this.person, {
    this.isConnected = false,
  }) : card = null;
  const ConnectLookup.organisation(ConnectCard this.card)
    : person = null,
      isConnected = false;

  final ConnectPerson? person;
  final ConnectCard? card;

  /// Already associates (`connected` on a lookup, `alreadyConnected` on a scan).
  final bool isConnected;

  factory ConnectLookup.fromJson(Map<String, dynamic> data) {
    if (data['type'] == 'person') {
      final user = ((data['user'] as Map?) ?? {}).cast<String, dynamic>();
      return ConnectLookup.person(
        ConnectPerson.fromJson(user),
        isConnected:
            data['connected'] == true || data['alreadyConnected'] == true,
      );
    }
    return ConnectLookup.organisation(ConnectCard.fromJson(data));
  }
}
