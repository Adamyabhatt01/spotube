import 'dart:math';
import 'package:uuid/uuid.dart';

abstract class PrimitiveUtils {
  static final Random _random = Random();
  static T getRandomElement<T>(List<T> list) {
    return list[_random.nextInt(list.length)];
  }

  static const uuid = Uuid();

  static String toReadableNumber(double num) {
    if (num > 999 && num < 99999) {
      return "${(num / 1000).toStringAsFixed(0)}K";
    } else if (num > 99999 && num < 999999) {
      return "${(num / 1000).toStringAsFixed(0)}K";
    } else if (num > 999999 && num < 999999999) {
      return "${(num / 1000000).toStringAsFixed(0)}M";
    } else if (num > 999999999) {
      return "${(num / 1000000000).toStringAsFixed(0)}B";
    } else {
      return num.toStringAsFixed(0);
    }
  }
}
