/// Which field rule failed. Returned by the pure validators so they stay
/// i18n-free and unit-testable; the widget maps each to a localized message.
///
/// Mirrors the server's field rules (CLIENT-AUTH-INTEGRATION.md §7.6) for nicer
/// UX only — the server remains authoritative (e.g. the "common password" check
/// is server-side and surfaces as a 400).
enum RegisterFieldError {
  emailRequired,
  emailInvalid,
  passwordRequired,
  passwordTooShort,
  passwordTooLong,
  displayNameRequired,
  displayNameTooLong,
  displayNameInvalid,
}

class RegisterValidators {
  const RegisterValidators._();

  static const passwordMin = 10;
  static const passwordMax = 128;
  static const displayNameMax = 100;
  static const emailMax = 254;

  // `local@domain.tld` shape; no spaces or control characters on either side.
  static final _emailRe = RegExp(r'^[^\s@\x00-\x1f]+@[^\s@\x00-\x1f]+\.[^\s@\x00-\x1f]+$');

  // Letters / marks / numbers in ANY script, plus space, underscore, hyphen.
  // Rejects `@`, URLs, and other punctuation (the name is interpolated into
  // emails). `unicode: true` is required for the `\p{…}` classes.
  static final _displayNameRe = RegExp(r'^[\p{L}\p{M}\p{N} _\-]+$', unicode: true);

  static RegisterFieldError? email(String value) {
    final v = value.trim();
    if (v.isEmpty) return RegisterFieldError.emailRequired;
    if (v.length > emailMax || !_emailRe.hasMatch(v)) return RegisterFieldError.emailInvalid;
    return null;
  }

  static RegisterFieldError? password(String value) {
    // Not trimmed — leading/trailing spaces can be intentional in a password.
    if (value.isEmpty) return RegisterFieldError.passwordRequired;
    if (value.length < passwordMin) return RegisterFieldError.passwordTooShort;
    if (value.length > passwordMax) return RegisterFieldError.passwordTooLong;
    return null;
  }

  static RegisterFieldError? displayName(String value) {
    final v = value.trim();
    if (v.isEmpty) return RegisterFieldError.displayNameRequired;
    if (v.length > displayNameMax) return RegisterFieldError.displayNameTooLong;
    if (!_displayNameRe.hasMatch(v)) return RegisterFieldError.displayNameInvalid;
    return null;
  }
}
