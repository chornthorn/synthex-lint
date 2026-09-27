import 'package:consumer/core/view_model.dart';

/// Deliberately sloppy view model: public mutable state, a non-final private
/// field, and a public setter. The `encapsulation` rule reports all three.
class HomeViewModel extends ViewModel {
  int _count = 0;

  String _title = '';

  String get title => _title;

  int get count => _count;

  void increment() {
    _count++;
  }
}
