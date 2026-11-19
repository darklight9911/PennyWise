import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rive/rive.dart' as rive;

/// How Penny, the pennyWise panda, feels.
///
/// The index is the `mood` number in the Rive file
/// (rive/penny, built by rive/tool/gen_penny.py), so keep the order.
enum PandaMood { idle, wave, happy, celebrate, worried, thinking, sleeping }

/// The Rive asset with Penny in it.
const pandaAsset = 'assets/rive/penny.riv';

/// Whether Penny is drawn with the Rive runtime.
///
/// Off by default, so widget tests (which have no native Rive library) and
/// devices where Rive failed to start show [PandaMascot.fallback] instead.
/// `main()` turns it on after `RiveNative.init()` succeeds.
final pandaAnimationsProvider = Provider<bool>((ref) => false);

/// One loaded copy of [pandaAsset], shared by every [PandaMascot].
final pandaFileLoaderProvider = Provider<rive.FileLoader>((ref) {
  final loader = rive.FileLoader.fromAsset(
    pandaAsset,
    riveFactory: rive.Factory.rive,
  );
  ref.onDispose(loader.dispose);
  return loader;
});

/// Starts the Rive runtime. Returns false when it cannot run here.
Future<bool> initPandaAnimations() async {
  try {
    await rive.RiveNative.init();
    return true;
  } on Object catch (e) {
    debugPrint('Rive could not start, Penny stays still: $e');
    return false;
  }
}

/// Penny the panda, animated in the given [mood].
///
/// Tapping her makes her giggle (handled inside the Rive file).
class PandaMascot extends ConsumerStatefulWidget {
  const PandaMascot({
    super.key,
    required this.mood,
    this.size = 120,
    this.giggleTrigger = 0,
    this.semanticLabel,
    this.fallback,
  });

  final PandaMood mood;
  final double size;

  /// Incrementing this fires Penny's Rive giggle trigger.
  final int giggleTrigger;

  /// Read by screen readers. Null means Penny is decoration only.
  final String? semanticLabel;

  /// Shown when animations are off or the file fails to load.
  final Widget? fallback;

  @override
  ConsumerState<PandaMascot> createState() => _PandaMascotState();
}

class _PandaMascotState extends ConsumerState<PandaMascot> {
  rive.ViewModelInstance? _vmi;

  @override
  void didUpdateWidget(PandaMascot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mood != widget.mood) _applyMood();
    if (oldWidget.giggleTrigger != widget.giggleTrigger) {
      _vmi?.trigger('tap')?.trigger();
    }
  }

  @override
  void dispose() {
    _vmi = null; // owned and disposed by RiveWidgetBuilder
    super.dispose();
  }

  void _applyMood() {
    _vmi?.number('mood')?.value = widget.mood.index.toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final fallback = widget.fallback ?? SizedBox.square(dimension: widget.size);
    Widget child;
    if (!ref.watch(pandaAnimationsProvider)) {
      child = fallback;
    } else {
      child = SizedBox.square(
        dimension: widget.size,
        child: rive.RiveWidgetBuilder(
          fileLoader: ref.watch(pandaFileLoaderProvider),
          dataBind: rive.DataBind.auto(),
          onLoaded: (state) {
            _vmi = state.viewModelInstance;
            _applyMood();
          },
          builder: (context, state) => switch (state) {
            rive.RiveLoaded() => rive.RiveWidget(
              controller: state.controller,
              fit: rive.Fit.contain,
            ),
            rive.RiveFailed() => fallback,
            _ => const SizedBox.shrink(),
          },
        ),
      );
    }
    final label = widget.semanticLabel;
    if (label == null) return ExcludeSemantics(child: child);
    return Semantics(image: true, label: label, child: child);
  }
}
