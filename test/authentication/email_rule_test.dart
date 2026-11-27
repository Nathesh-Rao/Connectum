import 'package:connectum/core/utils/email_rule.dart';
import 'package:connectum/features/authentication/auth_validators.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const refused = [
    'a@b..c',
    'a@b.c.',
    'a@.com',
    'a@b.c',
    'name@agile',
    'a@@b.cc',
    'a b@c.dd',
    'a\n@b.cc',
    'a@b\u200B.cc',
    'a\u200B@b.cc',
    'a\uFEFF@b.cc',
    'a@b.cc\u200B',
    'a\u0007@b.cc',
    'a@b.c1',
    '',
  ];
  const accepted = [
    'a@b.co',
    'me@corp.local',
    'first.last+tag@sub.example.com',
    'ünï@exämple.de',
    'राम@उदाहरण.भारत',
    '用户@例子.广告',
    'a@xn--bcher-kva.xn--p1ai',
    'a@b.c\u200Dd',
  ];

  for (final value in refused) {
    test('refuses ${value.codeUnits}', () {
      expect(EmailRule.isValid(value), isFalse);
      expect(AuthValidators.email(value), isNotNull);
    });
  }

  for (final value in accepted) {
    test('accepts $value', () {
      expect(EmailRule.isValid(value), isTrue);
      expect(AuthValidators.email(value), isNull);
    });
  }

  test('trims before validating', () {
    expect(AuthValidators.email('  a@b.co \n'), isNull);
  });

  test('empty and too long say so', () {
    expect(AuthValidators.email('   '), EmailRule.emptyMessage);
    expect(AuthValidators.email('${'a' * 250}@b.co'), EmailRule.tooLongMessage);
  });

  test('a name of only invisible characters is empty', () {
    expect(AuthValidators.personName('\u200B  '), isNotNull);
    expect(AuthValidators.enterpriseName('\uFEFF'), isNotNull);
    expect(AuthValidators.personName('Ann'), isNull);
  });
}
