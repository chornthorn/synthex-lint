import 'package:consumer/core/view_model.dart';

class SettingsViewModel extends ViewModel {
  final String _locale = 'en';

  String get description => 'Locale: $_locale';
}
