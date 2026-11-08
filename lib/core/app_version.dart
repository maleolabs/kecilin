/// Versi aplikasi yang ditampilkan di UI dan dipakai gerbang
/// sambutan/changelog. Flutter menyuntikkan FLUTTER_BUILD_NAME dari pubspec
/// saat build; defaultValue dipakai oleh test dan `dart run`.
const appVersion = String.fromEnvironment(
  'FLUTTER_BUILD_NAME',
  defaultValue: '1.1.0',
);
