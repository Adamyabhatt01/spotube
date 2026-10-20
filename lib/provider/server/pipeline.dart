import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shelf/shelf.dart';

final pipelineProvider = Provider((ref) {
  return const Pipeline();
});
