import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../core/emulator.dart';

/// Displays the live video output from [Emulator] at display refresh rate.
class AtariScreen extends StatefulWidget {
  const AtariScreen({super.key, this.onFpsTick});

  /// Called roughly once per second with the latest measured FPS.
  final ValueChanged<double>? onFpsTick;

  @override
  State<AtariScreen> createState() => _AtariScreenState();
}

class _AtariScreenState extends State<AtariScreen>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  ui.Image? _image;
  int _imgW = 0;
  int _imgH = 0;
  bool _decoding = false;
  DateTime _lastFpsReport = DateTime.now();

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration _) {
    final now = DateTime.now();
    if (now.difference(_lastFpsReport).inMilliseconds >= 500) {
      _lastFpsReport = now;
      widget.onFpsTick?.call(Emulator.instance.measuredFps);
    }

    if (_decoding) return;
    final frame = Emulator.instance.pollFrame();
    if (frame == null) return;

    _decoding = true;
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      frame.pixels,
      frame.width,
      frame.height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    completer.future.then((img) {
      if (!mounted) {
        img.dispose();
        return;
      }
      final prev = _image;
      setState(() {
        _image = img;
        _imgW = frame.width;
        _imgH = frame.height;
      });
      prev?.dispose();
      _decoding = false;
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final emu = Emulator.instance;
    final aspect = emu.aspect > 0 ? emu.aspect : (4.0 / 3.0);

    return Center(
      child: AspectRatio(
        aspectRatio: aspect,
        child: _image == null
            ? const ColoredBox(
                color: Colors.black,
                child: Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            : RawImage(
                image: _image,
                width: _imgW.toDouble(),
                height: _imgH.toDouble(),
                fit: BoxFit.fill,
                filterQuality:
                    emu.smoothScaling ? FilterQuality.low : FilterQuality.none,
              ),
      ),
    );
  }
}
