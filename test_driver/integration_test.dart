import 'package:integration_test/integration_test_driver.dart';

/// Driver for `flutter drive`, used when a driver harness is wanted:
///
///   flutter drive \
///     --driver=test_driver/integration_test.dart \
///     --target=integration_test/compression_test.dart \
///     --profile -d DEVICE_ID
///
/// `flutter drive` refuses `--release`, so this driver covers debug and profile
/// only. Minified-release behaviour is verified separately by installing the
/// release APK and exercising the UI by hand, because R8 is not applied in
/// either mode this driver supports.
Future<void> main() => integrationDriver();
