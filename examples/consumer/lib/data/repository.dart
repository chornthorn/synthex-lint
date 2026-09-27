import '../domain/repository.dart';

/// A correctly placed repository: named `*Repository` and implementing the
/// `domain` layer's `Repository` contract.
class InMemoryRepository implements Repository {}

/// Intentional violation of the `placement` rule: data-layer classes must
/// implement `Repository`.
class FakeRepository {}
