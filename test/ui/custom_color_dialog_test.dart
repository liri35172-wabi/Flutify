import 'package:flutify_app/l10n/app_localizations.dart';
import 'package:flutify_app/ui/screens/settings/widgets/custom_color_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'custom color dialog scrolls in a short window and keeps actions visible',
    (tester) async {
      tester.view.physicalSize = const Size(900, 420);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) =>
                        const CustomColorDialog(initial: Colors.blue),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final done = find.byType(FilledButton);
      expect(done.hitTestable(), findsOneWidget);
      expect(tester.getBottomLeft(done).dy, lessThanOrEqualTo(420));

      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -240),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
