import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// ~240 dpi on A4: sharp when printed, still small enough to send over LINE.
const exportPixelRatio = 2.5;

/// PNG of the widget under [key] (a RepaintBoundary) at its own, unscaled size.
Future<Uint8List> captureBoundary(GlobalKey key, {double pixelRatio = exportPixelRatio}) async {
  final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: pixelRatio);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

/// One A4 page (landscape for original + copy) with the bill image edge to edge.
Future<Uint8List> billPdf(Uint8List png, {required bool landscape, String title = ''}) {
  final doc = pw.Document(title: title, creator: 'ระบบจัดการออเดอร์ หิน-ทราย');
  doc.addPage(pw.Page(
    pageFormat: landscape ? PdfPageFormat.a4.landscape : PdfPageFormat.a4,
    margin: pw.EdgeInsets.zero,
    build: (_) => pw.Center(child: pw.Image(pw.MemoryImage(png), fit: pw.BoxFit.contain)),
  ));
  return doc.save();
}
