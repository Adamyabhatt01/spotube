import 'dart:io';
import 'package:hetu_script/hetu_script.dart';

void main(List<String> args) {
  final src = File(args[0]).readAsStringSync();
  final hetu = Hetu();
  hetu.init();
  final bytes = hetu.compile(src, sourceName: 'caelestia_theme');
  if (bytes.isEmpty) {
    print('COMPILE FAILED (empty bytecode)');
    exit(1);
  }
  File(args[1]).writeAsBytesSync(bytes);
  print('COMPILED ${bytes.length} bytes -> ${args[1]}');
}
