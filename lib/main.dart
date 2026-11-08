import 'dart:async';

import 'package:flutter/material.dart';

import 'app.dart';
import 'data/gallery.dart';
import 'data/history_store.dart';
import 'data/image_engine.dart';
import 'data/output_store.dart';
import 'data/pdf_engine.dart';
import 'data/settings_store.dart';
import 'state/compression_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // The gallery picker copies originals into the cache so the compressors can
  // open them as plain files. Those copies are worthless once the process that
  // picked them is gone, so a fresh start drops them instead of letting the
  // cache grow with every batch the user ever selected.
  unawaited(const GalleryService().clearCache());

  final history = await HistoryStore.create();
  final settings = await SettingsStore.create();

  final controller = CompressionController(
    imageEngine: const ImageCompressionEngine(),
    pdfEngine: const PdfCompressionEngine(),
    outputs: const OutputStore(),
    history: history,
    settings: settings,
  );

  runApp(
    KecilinApp(controller: controller, history: history, settings: settings),
  );
}
