import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/auth/register/model/register_validators.dart';

void main() {
  group('email', () {
    test('required when blank', () {
      expect(RegisterValidators.email(''), RegisterFieldError.emailRequired);
      expect(RegisterValidators.email('   '), RegisterFieldError.emailRequired);
    });

    test('valid shapes pass', () {
      expect(RegisterValidators.email('user@example.com'), isNull);
      expect(RegisterValidators.email('a.b+c@sub.example.co.uk'), isNull);
    });

    test('invalid shapes rejected', () {
      for (final bad in ['user', 'user@', '@example.com', 'user@example', 'a b@example.com', 'user@ex ample.com']) {
        expect(RegisterValidators.email(bad), RegisterFieldError.emailInvalid, reason: bad);
      }
    });

    test('over 254 chars rejected', () {
      expect(RegisterValidators.email('${'a' * 250}@e.com'), RegisterFieldError.emailInvalid);
    });
  });

  group('password', () {
    test('required when empty', () => expect(RegisterValidators.password(''), RegisterFieldError.passwordRequired));
    test('too short (<10)', () => expect(RegisterValidators.password('a' * 9), RegisterFieldError.passwordTooShort));
    test('exactly 10 passes', () => expect(RegisterValidators.password('a' * 10), isNull));
    test('exactly 128 passes', () => expect(RegisterValidators.password('a' * 128), isNull));
    test('too long (>128)', () => expect(RegisterValidators.password('a' * 129), RegisterFieldError.passwordTooLong));
  });

  group('displayName', () {
    test('required when blank', () {
      expect(RegisterValidators.displayName(''), RegisterFieldError.displayNameRequired);
      expect(RegisterValidators.displayName('   '), RegisterFieldError.displayNameRequired);
    });

    test('valid names in any script pass', () {
      for (final ok in ['Alex', 'José', '日本語', 'Владимир', 'Mary Jane', 'a_b-c', 'User 123']) {
        expect(RegisterValidators.displayName(ok), isNull, reason: ok);
      }
    });

    test('disallowed characters rejected', () {
      for (final bad in ['a@b', 'http://x', 'name!', 'a.b', 'foo/bar', 'quote"']) {
        expect(RegisterValidators.displayName(bad), RegisterFieldError.displayNameInvalid, reason: bad);
      }
    });

    test('100 passes, 101 too long', () {
      expect(RegisterValidators.displayName('a' * 100), isNull);
      expect(RegisterValidators.displayName('a' * 101), RegisterFieldError.displayNameTooLong);
    });
  });
}
