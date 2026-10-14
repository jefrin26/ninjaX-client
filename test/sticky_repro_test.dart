import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:james_bond/view/widgets/ui.dart';

void main() {
  testWidgets('sticky label does not crash', (t) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CustomScrollView(slivers: [
          const SliverAppBar(
              pinned: true, title: Text('T')),
          const StickyLabel('CONNECTION'),
          SliverToBoxAdapter(
            child: Container(
                height: 900, color: Colors.red),
          ),
          const StickyLabel('ABOUT'),
          const SliverToBoxAdapter(
            child: SizedBox(height: 200),
          ),
        ]),
      ),
    ));
    await t.pump();
    expect(find.text('CONNECTION'), findsOneWidget);
  });
}
