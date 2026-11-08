/// Catatan perubahan per versi, ditampilkan pada modal "Yang baru" ketika
/// aplikasi diperbarui. Tulis dari sudut pandang pengguna, bahasa Indonesia,
/// hanya fakta yang benar-benar ada di aplikasi.
library;

class ChangelogEntry {
  const ChangelogEntry({required this.title, required this.detail});

  final String title;
  final String detail;
}

const changelog = <String, List<ChangelogEntry>>{
  '1.1.0': [
    ChangelogEntry(
      title: 'Tampilan baru',
      detail:
          'Desain kaca minimalis dengan tema terang dan gelap yang lebih nyaman.',
    ),
    ChangelogEntry(
      title: 'Beranda lebih informatif',
      detail:
          'Statistik total penghematan, panel kompresi cepat, dan filter '
          'riwayat gambar/PDF.',
    ),
    ChangelogEntry(
      title: 'Riwayat dengan waktu',
      detail:
          'Setiap hasil kini menampilkan kapan kompresi terakhir dilakukan.',
    ),
    ChangelogEntry(
      title: 'Detail lebih rapi',
      detail:
          'Dialog penghapusan lebih jelas, animasi lebih halus, dan tata letak '
          'lebih rapi di seluruh aplikasi.',
    ),
  ],
};

/// Membandingkan dua versi "mayor.minor.patch". Entry tak terbaca dianggap 0,
/// jadi input rusak gagal aman (tidak memicu popup).
bool isNewerVersion(String candidate, String baseline) {
  final a = _parse(candidate);
  final b = _parse(baseline);
  for (var i = 0; i < 3; i++) {
    if (a[i] != b[i]) return a[i] > b[i];
  }
  return false;
}

List<int> _parse(String version) {
  final parts = version.split('.');
  return List.generate(
    3,
    (i) => i < parts.length ? int.tryParse(parts[i]) ?? 0 : 0,
  );
}
