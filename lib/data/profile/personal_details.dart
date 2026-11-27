import 'dart:convert';

import 'package:connectum/data/models/models.dart';

/// The private details of `profile.get` / `profile.update`.
class PersonalDetails {
  const PersonalDetails({
    this.gender = '',
    this.dob = '',
    this.address = '',
    this.education = '',
    this.skills = const [],
  });

  /// `male`, `female`, `other`, `prefer_not_to_say` or empty.
  final String gender;

  /// `YYYY-MM-DD` or empty.
  final String dob;
  final String address;
  final String education;
  final List<String> skills;

  static PersonalDetails fromJson(Map<String, dynamic> raw) {
    final skills = raw['skills'];
    return PersonalDetails(
      gender: idText(raw['gender']),
      dob: idText(raw['dob']),
      address: idText(raw['address']),
      education: idText(raw['education']),
      skills: skills is List
          ? [
              for (final s in skills)
                if (idText(s).isNotEmpty) idText(s),
            ]
          : const [],
    );
  }

  /// What differs from [saved], as the `profile.update` body. A field that is
  /// now empty is sent as null (an omitted key clears nothing on the server).
  Map<String, dynamic> changesFrom(PersonalDetails saved) {
    final out = <String, dynamic>{};
    void put(String key, String now, String before) {
      if (now != before) out[key] = now.isEmpty ? null : now;
    }

    put('gender', gender, saved.gender);
    put('dob', dob, saved.dob);
    put('address', address.trim(), saved.address.trim());
    put('education', education.trim(), saved.education.trim());
    if (!_sameList(skills, saved.skills)) {
      out['skills'] = skills.isEmpty ? null : skills;
    }
    return out;
  }

  static bool _sameList(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// The `profile.get` answer: the details plus what the header shows.
class ProfileRecord {
  const ProfileRecord({
    required this.details,
    this.roles = const [],
    this.designation = '',
  });

  final PersonalDetails details;
  final List<String> roles;

  /// `designation`, else `role`; empty when the server gives neither.
  final String designation;

  static ProfileRecord fromJson(Map<String, dynamic> raw) {
    final profile = raw['profile'];
    final map = profile is Map ? profile.cast<String, dynamic>() : raw;
    final roles = map['roles'];
    final designation = idText(map['designation']);
    return ProfileRecord(
      details: PersonalDetails.fromJson(map),
      roles: roles is List
          ? [
              for (final r in roles)
                if (idText(r).isNotEmpty) idText(r),
            ]
          : const [],
      designation: designation.isNotEmpty ? designation : idText(map['role']),
    );
  }
}

/// The limits the server enforces (`sd_users_employee.erl`).
class DetailsRules {
  DetailsRules._();

  static const addressBytes = 200;
  static const educationBytes = 120;
  static const maxSkills = 30;
  static const skillBytes = 40;

  static final _control = RegExp(r'[\u0000-\u001F\u007F]');

  static String clean(String text) => text.replaceAll(_control, '');

  /// The UTF-8 length, which is what the limits count.
  static int bytes(String text) => utf8.encode(text).length;

  /// [text] cut to at most [limit] bytes, never inside a character.
  static String cutBytes(String text, int limit) {
    if (bytes(text) <= limit) return text;
    final out = StringBuffer();
    var used = 0;
    for (final rune in text.runes) {
      final piece = String.fromCharCode(rune);
      final size = utf8.encode(piece).length;
      if (used + size > limit) break;
      used += size;
      out.write(piece);
    }
    return out.toString();
  }

  /// What is typed into a limited text field.
  static String typed(String text, int limit) => cutBytes(clean(text), limit);

  /// Comma separated skills: trimmed, blanks dropped, duplicates ignored
  /// (case-blind, the first spelling stays).
  static List<String> parseSkills(String text) {
    final seen = <String>{};
    final out = <String>[];
    for (final part in clean(text).split(',')) {
      final skill = part.trim();
      if (skill.isEmpty || !seen.add(skill.toLowerCase())) continue;
      out.add(skill);
    }
    return out;
  }

  /// The server's own wording for a skills list that would be refused, else
  /// null.
  static String? skillsError(List<String> skills) {
    if (skills.length > maxSkills) return 'At most $maxSkills skills.';
    if (skills.any((s) => bytes(s) > skillBytes)) {
      return 'Each skill must be $skillBytes characters or fewer.';
    }
    return null;
  }

  static final DateTime earliestBirth = DateTime(1900);

  static String dobToWire(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static DateTime? dobFromWire(String wire) {
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(wire);
    if (m == null) return null;
    final y = int.parse(m[1]!), mo = int.parse(m[2]!), d = int.parse(m[3]!);
    final date = DateTime(y, mo, d);
    if (date.year != y || date.month != mo || date.day != d) return null;
    return date;
  }
}
