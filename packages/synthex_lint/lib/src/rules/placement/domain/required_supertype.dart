/// Pure parsing of the supertype a violation asks for.
///
/// Kept out of the correction producer so the message shapes it accepts can be
/// tested without a resolved library.
library;

/// The single supertype a violation message asks for, or `null` when the
/// message does not name exactly one.
///
/// The `placement` rule reports two shapes:
///
/// * `Foo: must extend or implement 'Bar'.` — one supertype, which a fix can
///   add without choosing for the developer;
/// * `Foo: must extend or implement one of 'Bar', 'Baz'.` — several, where
///   adding one would be a guess, so no fix is offered.
String? requiredSupertypeFrom(String message) =>
    _singleSupertypePattern.firstMatch(message)?.group(1);

final _singleSupertypePattern = RegExp(
  r"must extend or implement '([^']+)'\.$",
);
