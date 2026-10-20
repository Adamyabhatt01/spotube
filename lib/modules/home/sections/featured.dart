import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Placeholder for the home featured section. Currently renders nothing;
/// a featured playlists API will be added for metadata plugins later,
/// at which point this section returns content again.
class HomeFeaturedSection extends HookConsumerWidget {
  const HomeFeaturedSection({super.key});

  @override
  Widget build(BuildContext context, ref) {
    return const SizedBox.shrink();
  }
}
