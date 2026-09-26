import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/collections/routes.dart';

/// Deep linking is currently disabled: the previous implementation
/// listened to `spotify:` links and shared media through a broadcast
/// stream that was never disposed. This no-op keeps the call site
/// stable until the custom metadata-provider link API lands, which
/// will add whichever link dependency it needs at that point.
void useDeepLinking(WidgetRef ref, AppRouter router) {}
