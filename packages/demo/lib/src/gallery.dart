import 'package:flutter/material.dart';

/// A showcase that the gallery lists: [description] states what to try on
/// the screen that [builder] makes.
class Showcase {
  const Showcase(this.title, this.description, this.builder);

  final String title;
  final String description;
  final WidgetBuilder builder;
}

/// The demo's home: one entry per showcase, each opening its screen, which
/// has its own map (design D190).
class Gallery extends StatelessWidget {
  const Gallery({super.key, required this.showcases});

  final List<Showcase> showcases;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Mapigrade demo')),
    body: ListView(
      padding: const EdgeInsets.all(8),
      children: [
        for (final showcase in showcases)
          Card(
            child: ListTile(
              title: Text(showcase.title),
              subtitle: Text(showcase.description),
              trailing: const Icon(Icons.chevron_right),
              onTap: () =>
                  Navigator.of(context)
                      .push(MaterialPageRoute(builder: showcase.builder)),
            ),
          ),
      ],
    ),
  );
}
