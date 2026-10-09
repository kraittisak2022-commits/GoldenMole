import 'dart:math';

final _rng = Random.secure();

String newId(String prefix) {
  final raw = List.generate(16, (_) => _rng.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  return '$prefix-$raw';
}
