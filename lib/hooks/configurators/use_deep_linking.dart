import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/collections/routes.dart';

/// Deep linking is currently disabled: the previous implementation
/// listened to `spotify:` links and shared media through a broadcast
/// stream that was never disposed. This no-op keeps the call site
/// stable until the custom metadata-provider link API lands. The
/// `app_links` dependency and native scheme registrants stay in place
/// for that future work.
void useDeepLinking(WidgetRef ref, AppRouter router) {}
