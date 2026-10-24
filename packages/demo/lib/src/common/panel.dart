import 'package:flutter/material.dart';

/// The card at the top left of a showcase screen: a header with a back
/// control when the route can be popped, [title] and [actions], then
/// [children], scrolling when they don't fit.
class DemoPanel extends StatelessWidget {
  const DemoPanel({
    super.key,
    required this.title,
    this.actions = const [],
    required this.children,
  });

  final String title;
  final List<Widget> actions;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Positioned(
      top: 0,
      left: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 300,
              maxHeight: MediaQuery.sizeOf(context).height - 96,
            ),
            child: Card(
              color: theme.colorScheme.surface.withValues(alpha: 0.92),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(12, 4, 4, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        if (ModalRoute.of(context)?.canPop ?? false)
                          const BackButton(),
                        Expanded(
                          child: Text(title, style: theme.textTheme.titleSmall),
                        ),
                        ...actions,
                      ],
                    ),
                    ...children,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
