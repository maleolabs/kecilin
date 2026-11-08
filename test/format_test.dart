import 'package:flutter_test/flutter_test.dart';
import 'package:kecilin/core/format.dart';

void main() {
  group('formatBytes', () {
    test('renders bytes below 1 KB as-is', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(999), '999 B');
    });

    test('renders kilobytes with one decimal below 10 KB', () {
      expect(formatBytes(1024), '1 KB');
      expect(formatBytes(1536), '1.5 KB');
      expect(formatBytes(204800), '200 KB');
    });

    test('renders megabytes', () {
      expect(formatBytes(1048576), '1 MB');
      expect(formatBytes(1572864), '1.5 MB');
      expect(formatBytes(41943040), '40 MB');
    });

    test('never renders negative sizes', () {
      expect(formatBytes(-10), '0 B');
    });
  });

  group('parseSize', () {
    test('accepts explicit units', () {
      expect(parseSize('200 KB'), 200 * 1024);
      expect(parseSize('200kb'), 200 * 1024);
      expect(parseSize('1.5 MB'), (1.5 * 1024 * 1024).round());
      expect(parseSize('750KB'), 750 * 1024);
    });

    test('rejects values without a unit', () {
      expect(parseSize('200'), isNull);
      expect(parseSize(''), isNull);
      expect(parseSize('banyak'), isNull);
    });

    test('rejects zero and negative sizes', () {
      expect(parseSize('0 KB'), isNull);
    });
  });

  group('file names', () {
    test('baseName handles both separators', () {
      expect(
        baseName('/storage/emulated/0/Download/dokumen.jpg'),
        'dokumen.jpg',
      );
      expect(baseName(r'C:\Users\me\dokumen.jpg'), 'dokumen.jpg');
      expect(baseName('dokumen.jpg'), 'dokumen.jpg');
    });

    test('stemOf drops the extension', () {
      expect(stemOf('/tmp/scan.kk.pdf'), 'scan.kk');
      expect(stemOf('no-extension'), 'no-extension');
    });

    test('sanitizeFileName strips characters Android dislikes', () {
      expect(sanitizeFileName('a/b:c*d?.pdf'), 'a_b_c_d_.pdf');
      expect(sanitizeFileName('   '), 'berkas');
    });
  });

  group('formatPercent', () {
    test('rounds big values and keeps one decimal for small ones', () {
      expect(formatPercent(0.6812), '68%');
      expect(formatPercent(0.0512), '5.1%');
      expect(formatPercent(0), '0.0%');
    });
  });
}
