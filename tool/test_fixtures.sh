#!/usr/bin/env bash
# Regenerates the fixtures used by integration_test/compression_test.dart.
#
# Every fixture is synthesised from scratch. No real document, photograph or
# personal record is read at any point, so this script is safe to run on any
# machine and safe to keep in version control.
#
# The fixtures are NOT bundled into release builds (see pubspec.yaml). Generate
# them, temporarily enable the `assets:` block, run the tests on a device, then
# disable it again and delete integration_test/assets/.
#
# Requires: imagemagick, ghostscript.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/integration_test/assets"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$OUT"

# 1) Photo-like 6 MP image: the 200 KB target test case.
#    Plasma noise + a document frame makes the source realistically expensive
#    to encode, so the compressor has to do real work to reach the target.
#    The identity printed on it is fabricated and deliberately unusable.
magick -size 2000x3000 plasma:fractal \
  -blur 0x1 \
  -modulate 108,22,100 \
  -fill '#ffffff' -draw 'roundrectangle 120,180 1880,1560 24,24' \
  -fill '#e9eef5' -draw 'roundrectangle 150,240 1050,980 16,16' \
  -fill '#1b2a41' -pointsize 64 -gravity northwest \
  -annotate +190+300 'CONTOH - BUKAN DOKUMEN ASLI' \
  -pointsize 40 \
  -annotate +190+420 'NIK   : 0000000000000000' \
  -annotate +190+490 'Nama  : NAMA CONTOH' \
  -annotate +190+560 ' Lahir: 01-01-2000' \
  -annotate +190+630 'Alamat: JL. CONTOH NO. 1' \
  -annotate +190+700 '        KOTA CONTOH' \
  -annotate +190+770 'Agama : CONTOH' \
  -annotate +190+840 'Pekerjaan: CONTOH' \
  -pointsize 34 -fill '#6b7a90' \
  -annotate +190+1470 'SPECIMEN - SYNTHETIC TEST FIXTURE' \
  -gravity north -fill '#1b2a4114' -pointsize 180 -annotate +0+1180 'SPECIMEN' \
  -quality 95 -sampling-factor 4:2:0 -strip \
  "$OUT/sample-photo.jpg"

# 2) Scanner-like pages: 2400x3200 at 150 dpi.
magick -size 2400x3200 gradient:'#fbfbf7-#d8d8d0' -fill '#111' -pointsize 90 \
  -annotate +150+300 'SURAT KETERANGAN' -annotate +150+450 'Nomor: 001/2026' \
  -annotate +150+600 'Yang bertanda tangan di bawah ini menerangkan' \
  -annotate +150+720 'bahwa nama tersebut di atas adalah benar.' \
  -quality 95 -density 150 "$TMP/page.jpg"

for i in 1 2 3 4; do cp "$TMP/page.jpg" "$TMP/p$i.jpg"; done
magick "$TMP/p1.jpg" "$TMP/p2.jpg" "$TMP/p3.jpg" "$TMP/p4.jpg" \
  -compress JPEG -quality 95 -density 150 "$OUT/scan-4p.pdf"

for i in $(seq 1 12); do cp "$TMP/page.jpg" "$TMP/q$i.jpg"; done
magick $(ls "$TMP"/q*.jpg | sort -V) \
  -compress JPEG -quality 95 -density 150 "$OUT/scan-12p.pdf"

# 3) Text-only PDF (worst case for Ringan: nothing to re-encode).
cat > "$TMP/text.ps" <<'PS'
%!PS-Adobe-3.0
/Helvetica findfont 16 scalefont setfont
72 720 moveto (PERJANJIAN KERJA SAMA) show
/Helvetica findfont 11 scalefont setfont
72 690 moveto (Nomor: 042/PKS/XI/2026) show
72 660 moveto (Pada hari ini para pihak sepakat mengadakan perjanjian kerja sama.) show
72 640 moveto (Pasal 1 - Ruang Lingkup. Pihak Pertama menyediakan layanan pengembangan) show
72 625 moveto (perangkat lunak pemeliharaan sistem dan dukungan teknis.) show
72 595 moveto (Pasal 2 - Jangka Waktu. Perjanjian berlaku dua belas bulan sejak) show
72 580 moveto (tanggal ditandatangani dan dapat diperpanjang atas kesepakatan tertulis.) show
showpage
72 720 moveto (LAMPIRAN A) show
72 690 moveto (Rincian biaya layanan per bulan sebagai berikut.) show
showpage
PS
gs -q -dNOPAUSE -dBATCH -sDEVICE=pdfwrite -dCompatibilityLevel=1.7 \
  -sOutputFile="$OUT/text-only.pdf" "$TMP/text.ps"

# 4) Mixed document: 2 text pages + 4 pages sharing ONE JPEG XObject.
#    Ghostscript deduplicates the identical images, which is exactly what the
#    per-stream dedupe in PdfLightCompressor has to survive.
gs -q -dNOPAUSE -dBATCH -sDEVICE=pdfwrite -dCompatibilityLevel=1.7 \
  -sOutputFile="$OUT/mixed-6p.pdf" "$OUT/text-only.pdf" "$OUT/scan-4p.pdf"

ls -lh "$OUT"
cat <<'NOTE'

Next: add `- integration_test/assets/` to the existing `assets:` list in
pubspec.yaml (one list, not a second key), then run

  flutter test integration_test/compression_test.dart -d DEVICE_ID

Afterwards remove that line again and delete integration_test/assets/*.
NOTE
