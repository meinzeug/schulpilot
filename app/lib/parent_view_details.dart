import 'package:flutter/material.dart';

/// Optional parent tools retain their local drafts while remaining scoped to
/// the account, child and source chosen by the caller. Opening is view-only.
class ParentViewDetails extends StatefulWidget {
  final String title;
  final String? subtitle;
  final Object scope;
  final bool Function() isCurrent;
  final List<Widget> children;
  final bool initiallyExpanded;
  const ParentViewDetails({
    super.key,
    required this.title,
    this.subtitle,
    required this.scope,
    required this.isCurrent,
    required this.children,
    this.initiallyExpanded = false,
  });

  @override
  State<ParentViewDetails> createState() => _ParentViewDetailsState();
}

class _ParentViewDetailsState extends State<ParentViewDetails> {
  late bool expanded = widget.initiallyExpanded;
  PageStorageBucket? storage;
  Object? restoredScope;

  void restoreExpansion() {
    final saved = storage?.readState(context, identifier: widget.scope);
    expanded = saved is bool ? saved : widget.initiallyExpanded;
    restoredScope = widget.scope;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextStorage = PageStorage.maybeOf(context);
    if (!identical(storage, nextStorage) || restoredScope != widget.scope) {
      storage = nextStorage;
      restoreExpansion();
    }
  }

  @override
  void didUpdateWidget(covariant ParentViewDetails oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scope != widget.scope) {
      restoreExpansion();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isCurrent()) return const SizedBox.shrink();
    final scope = widget.scope;
    final current = widget.isCurrent;
    final route = ModalRoute.of(context);
    return ExpansionTile(
      key: ValueKey(scope),
      title: Text(
        widget.title,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
      subtitle: widget.subtitle == null ? null : Text(widget.subtitle!),
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(top: 8, bottom: 8),
      maintainState: true,
      initiallyExpanded: expanded,
      shape: const Border(),
      collapsedShape: const Border(),
      onExpansionChanged: (value) {
        if (!mounted ||
            scope != widget.scope ||
            !current() ||
            !widget.isCurrent() ||
            route?.isCurrent == false) {
          return;
        }
        storage?.writeState(context, value, identifier: scope);
        setState(() => expanded = value);
      },
      children: [
        ExcludeFocus(
          excluding: !expanded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: widget.children,
          ),
        ),
      ],
    );
  }
}
