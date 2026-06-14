// Builds the adaptive-icon foreground from the user-supplied full icon:
//   assets/icon/app_icon.png   (their design — legacy/full icon, used as-is)
//   assets/icon/foreground.png (their design shrunk into the adaptive safe zone)
// and reports the icon's corner colour to use as adaptive_icon_background.
//
// Run: dart run tool/make_icon.dart   then   dart run flutter_launcher_icons
import 'dart:io';
import 'package:image/image.dart' as img;

const _size = 1024;
const _scale = 0.80; // fit the design inside the adaptive safe zone

void main() {
  final src = img.decodePng(File('assets/icon/app_icon.png').readAsBytesSync());
  if (src == null) {
    stderr.writeln('Could not read assets/icon/app_icon.png');
    exit(1);
  }

  // Sample the corner for the adaptive background colour (matches the tile so
  // the shrunk foreground blends into the masked area).
  final c = src.getPixel(2, 2);
  final hex = '#'
      '${c.r.toInt().toRadixString(16).padLeft(2, '0')}'
      '${c.g.toInt().toRadixString(16).padLeft(2, '0')}'
      '${c.b.toInt().toRadixString(16).padLeft(2, '0')}';
  stdout.writeln('adaptive_icon_background should be: $hex');

  final dim = (_size * _scale).round();
  final resized = img.copyResize(src,
      width: dim, height: dim, interpolation: img.Interpolation.cubic);
  final canvas = img.Image(width: _size, height: _size, numChannels: 4);
  final offset = (_size - dim) ~/ 2;
  img.compositeImage(canvas, resized, dstX: offset, dstY: offset);
  File('assets/icon/foreground.png').writeAsBytesSync(img.encodePng(canvas));

  stdout.writeln('Wrote assets/icon/foreground.png (${_scale}x of your icon)');
}
