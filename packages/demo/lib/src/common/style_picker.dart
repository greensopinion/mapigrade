import 'package:flutter/material.dart';

import 'styles.dart';

/// A choice of [demoStyles].
class StylePicker extends StatelessWidget {
  const StylePicker({super.key, required this.value, required this.onChanged});

  final DemoStyle value;
  final ValueChanged<DemoStyle> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Text('Style'),
      const SizedBox(width: 12),
      Expanded(
        child: DropdownButton<DemoStyle>(
          isExpanded: true,
          value: value,
          items: [
            for (final style in demoStyles)
              DropdownMenuItem(value: style, child: Text(style.name)),
          ],
          onChanged: (style) => onChanged(style!),
        ),
      ),
    ],
  );
}
