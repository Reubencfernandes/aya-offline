import 'package:flutter/material.dart';

enum AyaPageMode { translate, ask }

class AyaPageModeSwitcher extends StatelessWidget {
  const AyaPageModeSwitcher({
    super.key,
    required this.current,
    required this.activeColor,
    required this.onTranslate,
    required this.onAsk,
  });

  final AyaPageMode current;
  final Color activeColor;
  final VoidCallback onTranslate;
  final VoidCallback onAsk;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.grey.shade100,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ModeButton(
              label: 'Translate',
              selected: current == AyaPageMode.translate,
              activeColor: activeColor,
              onTap: onTranslate,
            ),
            _ModeButton(
              label: 'Ask',
              selected: current == AyaPageMode.ask,
              activeColor: activeColor,
              onTap: onAsk,
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.label,
    required this.selected,
    required this.activeColor,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color activeColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(15),
      onTap: selected ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: selected
                ? activeColor.withValues(alpha: 0.35)
                : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? activeColor : Colors.grey.shade600,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
