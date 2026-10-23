import 'package:flutify_app/ui/screens/player/lyrics/lyric_line_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 单行歌词的译文渲染：有译文时多一行小字，间奏不渲染译文。
void main() {
  Widget wrap(Widget child, {bool disableAnimations = false}) => MaterialApp(
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(disableAnimations: disableAnimations),
        child: Scaffold(body: child),
      ),
    ),
  );

  testWidgets('译文在原文下方以小字渲染', (tester) async {
    await tester.pumpWidget(
      wrap(
        const LyricLineView(
          text: 'walking down the road',
          translation: '走在路上',
          distance: 0,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('walking down the road'), findsOneWidget);
    expect(find.text('走在路上'), findsOneWidget);
    final original = tester.widget<Text>(find.text('walking down the road'));
    final translation = tester.widget<Text>(find.text('走在路上'));
    expect(
      translation.style?.fontSize,
      lessThan(original.style!.fontSize!),
      reason: '译文必须比原文小',
    );
  });

  testWidgets(
    'Android ticker moves only an overflowing focused line left once',
    (tester) async {
      tester.view.physicalSize = const Size(180, 300);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        wrap(
          const LyricLineView(
            text: 'A very long lyric line that must move horizontally once',
            translation: '译文保持独立显示',
            distance: 0,
            horizontalTicker: true,
            fontSize: 24,
          ),
        ),
      );
      await tester.pump();
      final scrollable = find.descendant(
        of: find.byType(LyricLineView),
        matching: find.byType(Scrollable),
      );
      expect(scrollable, findsOneWidget);
      final scrollViewFinder = find.descendant(
        of: find.byType(LyricLineView),
        matching: find.byType(SingleChildScrollView),
      );
      final scrollWidget = tester.widget<SingleChildScrollView>(
        scrollViewFinder,
      );
      expect(scrollWidget.scrollDirection, Axis.horizontal);
      expect(scrollWidget.clipBehavior, Clip.hardEdge);
      final viewportWidth = tester.getSize(scrollViewFinder).width;
      final lyricFinder = find.text(
        'A very long lyric line that must move horizontally once',
      );
      final lyricText = tester.widget<Text>(lyricFinder);
      expect(lyricText.maxLines, 1);
      expect(lyricText.softWrap, isFalse);
      expect(lyricText.overflow, TextOverflow.clip);
      final contentWidth = tester.getSize(lyricFinder).width;
      final initialTextX = tester.getTopLeft(lyricFinder).dx;
      expect(viewportWidth, greaterThan(0));
      expect(viewportWidth, lessThanOrEqualTo(180));
      expect(contentWidth, greaterThan(viewportWidth));
      final state = tester.state<ScrollableState>(scrollable);
      expect(state.position.viewportDimension, closeTo(viewportWidth, 0.1));
      expect(state.position.maxScrollExtent, greaterThan(0));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(seconds: 1));
      final midPass = state.position.pixels;
      expect(midPass, greaterThan(0));
      expect(midPass, lessThan(state.position.maxScrollExtent));
      expect(
        tester.getTopLeft(lyricFinder).dx,
        lessThan(initialTextX),
        reason: 'the glyphs must travel left through the clipped viewport',
      );
      await tester.pump(const Duration(seconds: 6));
      expect(
        state.position.pixels,
        closeTo(state.position.maxScrollExtent, 0.1),
      );
      final stoppedAt = state.position.pixels;
      await tester.pump(const Duration(seconds: 3));
      expect(state.position.pixels, closeTo(stoppedAt, 0.1));
      expect(find.text('译文保持独立显示'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('focus opacity animation does not reset the one-pass ticker', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(180, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    Widget line(int distance) => wrap(
      LyricLineView(
        text:
            'A very long lyric line that should continue moving while it fades',
        distance: distance,
        horizontalTicker: true,
        fontSize: 24,
      ),
    );

    await tester.pumpWidget(line(1));
    await tester.pumpWidget(line(0));
    await tester.pump();
    final scrollable = find.descendant(
      of: find.byType(LyricLineView),
      matching: find.byType(Scrollable),
    );
    final state = tester.state<ScrollableState>(scrollable);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(milliseconds: 120));
    expect(state.position.pixels, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('non-overflowing focused lyrics stay still', (tester) async {
    tester.view.physicalSize = const Size(320, 300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      wrap(
        const LyricLineView(text: 'ok', distance: 0, horizontalTicker: true),
      ),
    );
    await tester.pump();
    expect(
      find.descendant(
        of: find.byType(LyricLineView),
        matching: find.byType(Scrollable),
      ),
      findsNothing,
      reason: 'a short lyric should not create a horizontal scroll extent',
    );
    final initialTextX = tester.getTopLeft(find.text('ok')).dx;
    await tester.pump(const Duration(seconds: 3));
    expect(tester.getTopLeft(find.text('ok')).dx, closeTo(initialTextX, 0.01));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'reduced motion keeps long active lyrics clipped on one line without movement',
    (tester) async {
      tester.view.physicalSize = const Size(180, 300);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        wrap(
          const LyricLineView(
            text:
                'A very long lyric line that must remain still for reduced motion',
            distance: 0,
            horizontalTicker: true,
            fontSize: 24,
          ),
          disableAnimations: true,
        ),
      );
      await tester.pump();
      final scrollable = find.descendant(
        of: find.byType(LyricLineView),
        matching: find.byType(Scrollable),
      );
      final scrollViewFinder = find.descendant(
        of: find.byType(LyricLineView),
        matching: find.byType(SingleChildScrollView),
      );
      expect(scrollViewFinder, findsOneWidget);
      final state = tester.state<ScrollableState>(scrollable);
      final lyricFinder = find.text(
        'A very long lyric line that must remain still for reduced motion',
      );
      final text = tester.widget<Text>(lyricFinder);
      expect(text.maxLines, 1);
      expect(text.softWrap, isFalse);
      expect(text.overflow, TextOverflow.clip);
      final viewportWidth = tester.getSize(scrollViewFinder).width;
      expect(viewportWidth, greaterThan(0));
      expect(viewportWidth, lessThanOrEqualTo(180));
      expect(tester.getSize(lyricFinder).width, greaterThan(viewportWidth));
      expect(state.position.viewportDimension, closeTo(viewportWidth, 0.1));
      expect(state.position.maxScrollExtent, greaterThan(0));
      final initialTextX = tester.getTopLeft(lyricFinder).dx;
      await tester.pump(const Duration(seconds: 4));
      expect(state.position.pixels, 0);
      expect(tester.getTopLeft(lyricFinder).dx, closeTo(initialTextX, 0.01));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'non-focused rows and default lyrics keep their existing wrapping',
    (tester) async {
      await tester.pumpWidget(
        wrap(
          const LyricLineView(
            text:
                'A very long lyric line that remains in the normal list layout',
            distance: 1,
            horizontalTicker: true,
          ),
        ),
      );
      expect(find.byType(Scrollable), findsNothing);
      expect(
        find.text(
          'A very long lyric line that remains in the normal list layout',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('间奏行只显示圆点，不渲染译文', (tester) async {
    await tester.pumpWidget(
      wrap(const LyricLineView(text: '', translation: '走在路上', distance: 0)),
    );
    await tester.pumpAndSettle();
    expect(find.text('走在路上'), findsNothing);
  });

  testWidgets('无译文时不渲染第二行', (tester) async {
    await tester.pumpWidget(
      wrap(const LyricLineView(text: 'walking down the road', distance: 0)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Text), findsNWidgets(1));
  });

  testWidgets('译文展开进度同步控制原文位置、透明度和行高', (tester) async {
    Future<void> show(double progress) async {
      await tester.pumpWidget(
        wrap(
          LyricLineView(
            text: 'walking down the road',
            translation: '走在路上\n寻找前方的方向',
            translationProgress: progress,
            distance: 0,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await show(0);
    final collapsedY = tester.getTopLeft(find.text('walking down the road')).dy;
    final collapsedHeight = tester.getSize(find.byType(LyricLineView)).height;
    expect(find.text('走在路上\n寻找前方的方向'), findsNothing);
    await show(0.5);
    final intermediateHeight = tester
        .getSize(find.byType(LyricLineView))
        .height;
    expect(
      tester.getTopLeft(find.text('walking down the road')).dy,
      closeTo(collapsedY - 4.5, 0.01),
    );
    expect(
      tester.widget<Text>(find.text('走在路上\n寻找前方的方向')).style!.color!.a,
      closeTo(0.31, 0.01),
    );
    expect(
      find.ancestor(
        of: find.text('走在路上\n寻找前方的方向'),
        matching: find.byType(ClipRect),
      ),
      findsNothing,
      reason: '淡入时应保留完整字形，而不是裁出半截文字',
    );
    await show(1);
    final expandedHeight = tester.getSize(find.byType(LyricLineView)).height;
    expect(
      tester.getTopLeft(find.text('walking down the road')).dy,
      closeTo(collapsedY - 9, 0.01),
    );
    expect(
      intermediateHeight - collapsedHeight,
      closeTo((expandedHeight - collapsedHeight) * 0.5, 0.01),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('缺失译文和间奏不参与双语位移动画', (tester) async {
    for (final text in ['原文没有译词', '♪', '']) {
      await tester.pumpWidget(
        wrap(LyricLineView(text: text, translationProgress: 0, distance: 0)),
      );
      await tester.pumpAndSettle();
      final original = find.byType(Text);
      final collapsedY = tester.getTopLeft(original).dy;
      final collapsedHeight = tester.getSize(find.byType(LyricLineView)).height;
      await tester.pumpWidget(
        wrap(
          LyricLineView(
            text: text,
            translation: text == '原文没有译词' ? '  ' : '不应显示',
            translationProgress: 1,
            distance: 0,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Text), findsOneWidget);
      expect(tester.getTopLeft(original).dy, collapsedY);
      expect(
        tester.getSize(find.byType(LyricLineView)).height,
        collapsedHeight,
      );
    }
  });
}
