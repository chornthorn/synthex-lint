import 'package:synthex_lint/src/rules/placement/domain/required_supertype.dart';
import 'package:test/test.dart';

void main() {
  test('reads the single required supertype', () {
    expect(
      requiredSupertypeFrom(
        "FakeRepository: must extend or implement 'Repository'.",
      ),
      'Repository',
    );
  });

  test('refuses a choice between several supertypes', () {
    expect(
      requiredSupertypeFrom(
        "FakeRepository: must extend or implement one of 'Repository', "
        "'DataSource'.",
      ),
      isNull,
    );
  });

  test('ignores a message that asks for nothing', () {
    expect(
      requiredSupertypeFrom(
        "HomeScreen: must not extend or implement 'ChangeNotifier'.",
      ),
      isNull,
    );
  });

  test('ignores a naming violation', () {
    expect(
      requiredSupertypeFrom("HomeBadge: name must end with 'Widget'."),
      isNull,
    );
  });
}
