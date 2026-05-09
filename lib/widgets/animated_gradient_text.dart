import 'package:flutter/material.dart';

class AnimatedGradientText extends StatefulWidget {
  final String text;
  final List<Color> colors;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;
  final Duration duration;
  final String? semanticsLabel;

  const AnimatedGradientText(
    this.text, {
    super.key,
    required this.colors,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
    this.duration = const Duration(milliseconds: 3600),
    this.semanticsLabel,
  });

  @override
  State<AnimatedGradientText> createState() => _AnimatedGradientTextState();
}

class _AnimatedGradientTextState extends State<AnimatedGradientText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant AnimatedGradientText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.duration != widget.duration) {
      _controller.duration = widget.duration;
      if (_controller.isAnimating) {
        _controller.repeat(reverse: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.colors.length < 2) {
      return Text(
        widget.text,
        style: widget.colors.isEmpty
            ? widget.style
            : widget.style?.copyWith(color: widget.colors.first),
        textAlign: widget.textAlign,
        maxLines: widget.maxLines,
        overflow: widget.overflow,
        semanticsLabel: widget.semanticsLabel,
      );
    }

    final disableAnimations = MediaQuery.maybeOf(context)?.disableAnimations;
    if (disableAnimations ?? false) {
      return _GradientText(
        text: widget.text,
        colors: widget.colors,
        value: 0.5,
        style: widget.style,
        textAlign: widget.textAlign,
        maxLines: widget.maxLines,
        overflow: widget.overflow,
        semanticsLabel: widget.semanticsLabel,
      );
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return _GradientText(
          text: widget.text,
          colors: widget.colors,
          value: Curves.easeInOutSine.transform(_controller.value),
          style: widget.style,
          textAlign: widget.textAlign,
          maxLines: widget.maxLines,
          overflow: widget.overflow,
          semanticsLabel: widget.semanticsLabel,
        );
      },
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

class _GradientText extends StatelessWidget {
  final String text;
  final List<Color> colors;
  final double value;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;
  final String? semanticsLabel;

  const _GradientText({
    required this.text,
    required this.colors,
    required this.value,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
    this.semanticsLabel,
  });

  @override
  Widget build(BuildContext context) {
    final begin = Alignment.lerp(
      const Alignment(-1.8, 0),
      const Alignment(0.3, 0),
      value,
    )!;
    final end = Alignment.lerp(
      const Alignment(-0.3, 0),
      const Alignment(1.8, 0),
      value,
    )!;

    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) {
        return LinearGradient(
          begin: begin,
          end: end,
          colors: [colors.last, ...colors, colors.first],
        ).createShader(bounds);
      },
      child: Text(
        text,
        style: style,
        textAlign: textAlign,
        maxLines: maxLines,
        overflow: overflow,
        semanticsLabel: semanticsLabel,
      ),
    );
  }
}
