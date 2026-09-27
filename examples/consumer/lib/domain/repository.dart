/// The repository contract the `data` layer implements.
///
/// The `placement` rule requires every class in `lib/src/data/**` to have this
/// supertype, so the contract lives in the innermost layer and `data`
/// implements it.
abstract class Repository {}
