import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:visibility_detector/visibility_detector.dart';

class Waypoint extends HookWidget {
  final FutureOr<void> Function()? onTouchEdge;
  final Widget? child;
  final ScrollController controller;
  final bool isGrid;

  const Waypoint({
    super.key,
    required this.controller,
    this.isGrid = false,
    this.onTouchEdge,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    // One-trigger-per-load-cycle: suppresses repeated edge callbacks while a
    // single onTouchEdge invocation is still in flight. The notifier itself
    // also enforces single-flight fetching; this is redundant suppression.
    final isTriggering = useRef(false);

    useEffect(() {
      if (isGrid) {
        return null;
      }
      Future<void> listener() async {
        // nextPageTrigger will have a value equivalent to 80% of the list size.
        final nextPageTrigger = 0.8 * controller.position.maxScrollExtent;

        // scrollController fetches the next paginated data when the current
        // position of the user on the screen has surpassed
        if (!isTriggering.value &&
            controller.position.pixels >= nextPageTrigger &&
            context.mounted) {
          isTriggering.value = true;
          try {
            await onTouchEdge?.call();
          } finally {
            isTriggering.value = false;
          }
        }
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (controller.hasClients && context.mounted) {
          listener();
          controller.addListener(listener);
        }
      });
      return () => controller.removeListener(listener);
    }, [controller, onTouchEdge]);

    if (isGrid) {
      return VisibilityDetector(
        key: const Key("waypoint"),
        onVisibilityChanged: (info) async {
          if (info.visibleFraction > 0 &&
              !isTriggering.value &&
              context.mounted) {
            isTriggering.value = true;
            try {
              await onTouchEdge?.call();
            } finally {
              isTriggering.value = false;
            }
          }
        },
        child: child ?? Container(),
      );
    }

    return child ?? Container();
  }
}
