import 'package:dio/dio.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/services/dio/dio.dart';

/// The app's shared HTTP client.
///
/// Container-scoped so its lifetime is explicit and tests can override it
/// with a client carrying their own adapter instead of mutating a global.
final appDioProvider = Provider<Dio>((ref) => createAppDio());
