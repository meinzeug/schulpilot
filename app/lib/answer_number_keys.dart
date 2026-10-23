import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A convenience for visible choices only. Unhandled editing/browser keys
/// continue through Flutter's focus chain; no action ever submits an answer.
class AnswerNumberKeys extends StatelessWidget {
  final Widget child;
  final bool Function() isCurrent;
  final int optionCount;
  final ValueChanged<int> onSelect;
  final FocusNode? focusNode;
  const AnswerNumberKeys({
    super.key,
    required this.child,
    required this.isCurrent,
    required this.optionCount,
    required this.onSelect,
    this.focusNode,
  });

  static bool get typingIntoField =>
      FocusManager.instance.primaryFocus?.context?.widget is EditableText ||
      FocusManager.instance.primaryFocus?.context
              ?.findAncestorWidgetOfExactType<EditableText>() !=
          null;

  @override
  Widget build(BuildContext context) => Focus(
    autofocus: true,
    focusNode: focusNode,
    onKeyEvent: (node, event) {
      if (event is! KeyDownEvent ||
          !isCurrent() ||
          typingIntoField ||
          HardwareKeyboard.instance.isControlPressed ||
          HardwareKeyboard.instance.isMetaPressed ||
          HardwareKeyboard.instance.isAltPressed ||
          HardwareKeyboard.instance.isShiftPressed) {
        return KeyEventResult.ignored;
      }
      const keys = [
        LogicalKeyboardKey.digit1,
        LogicalKeyboardKey.digit2,
        LogicalKeyboardKey.digit3,
        LogicalKeyboardKey.digit4,
        LogicalKeyboardKey.digit5,
        LogicalKeyboardKey.digit6,
        LogicalKeyboardKey.digit7,
        LogicalKeyboardKey.digit8,
        LogicalKeyboardKey.digit9,
      ];
      final index = keys.indexOf(event.logicalKey);
      if (index < 0 || index >= optionCount) return KeyEventResult.ignored;
      onSelect(index);
      return KeyEventResult.handled;
    },
    child: child,
  );
}
