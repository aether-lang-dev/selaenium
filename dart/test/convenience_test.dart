// No-browser unit tests for the convenience tier: Keys code points,
// WebDriverWait polling, Select option-picking, and Actions W3C JSON. The
// wait/Select/Actions helpers are exercised against plain fakes implementing
// the ElementLike/DriverLike seams — no libselenium_core.so, no chromedriver.
import 'package:selenium/selenium.dart';
import 'package:selenium/src/webdriver.dart' show ElementLike, DriverLike;
import 'package:test/test.dart';

/// A fake <option> (or any element) whose state is set directly in the test.
class FakeOption implements ElementLike {
  @override
  final String id;
  @override
  final String tagName;
  @override
  final String text;
  final Map<String, dynamic> attrs;
  bool selected;
  int clicks = 0;

  FakeOption(this.id,
      {this.tagName = 'option',
      this.text = '',
      Map<String, dynamic>? attributes,
      this.selected = false})
      : attrs = attributes ?? const {};

  @override
  bool isSelected() => selected;
  @override
  bool isEnabled() => true;
  @override
  bool isDisplayed() => true;
  @override
  void click() {
    clicks++;
    selected = !selected; // a click toggles selection, as a real <option> does
  }

  @override
  dynamic getAttribute(String name) => attrs[name];
  @override
  List<ElementLike> findElements(By by) => const [];
}

/// A fake <select> carrying a fixed option list.
class FakeSelect extends FakeOption {
  final List<FakeOption> _options;
  FakeSelect(this._options,
      {String tag = 'select', Map<String, dynamic>? attrs})
      : super('sel', tagName: tag, attributes: attrs ?? const {});

  @override
  List<ElementLike> findElements(By by) {
    expect(by.strategy, 'tag name');
    expect(by.value, 'option');
    return _options;
  }
}

/// A fake driver that records the actions payload perform() posts.
class FakeDriver implements DriverLike {
  List<dynamic>? posted;
  @override
  void performActions(List<dynamic> actions) => posted = actions;
}

const _elementKey = 'element-6066-11e4-a52e-4f735466cecf';

void main() {
  group('Keys', () {
    test('common code points are the W3C PUA values', () {
      expect(Keys.enter.codeUnitAt(0), 0xE007);
      expect(Keys.tab.codeUnitAt(0), 0xE004);
      expect(Keys.escape.codeUnitAt(0), 0xE00C);
      expect(Keys.nul.codeUnitAt(0), 0xE000);
      expect(Keys.space.codeUnitAt(0), 0xE00D);
      expect(Keys.f1.codeUnitAt(0), 0xE031);
      expect(Keys.f12.codeUnitAt(0), 0xE03C);
      expect(Keys.meta.codeUnitAt(0), 0xE03D);
    });

    test('aliases share the canonical code point', () {
      expect(Keys.backSpace, Keys.backspace);
      expect(Keys.leftShift, Keys.shift);
      expect(Keys.leftControl, Keys.control);
      expect(Keys.arrowLeft, Keys.left);
      expect(Keys.command, Keys.meta);
    });

    test('the whole catalog is one PUA code unit, U+E000..U+E03D', () {
      for (final k in [
        Keys.nul,
        Keys.cancel,
        Keys.help,
        Keys.backspace,
        Keys.tab,
        Keys.clear,
        Keys.returnKey,
        Keys.enter,
        Keys.shift,
        Keys.control,
        Keys.alt,
        Keys.pause,
        Keys.escape,
        Keys.space,
        Keys.pageUp,
        Keys.pageDown,
        Keys.end,
        Keys.home,
        Keys.left,
        Keys.up,
        Keys.right,
        Keys.down,
        Keys.insert,
        Keys.delete,
        Keys.semicolon,
        Keys.equals,
        Keys.numpad0,
        Keys.numpad9,
        Keys.multiply,
        Keys.divide,
        Keys.f1,
        Keys.f12,
        Keys.meta,
      ]) {
        expect(k.length, 1);
        final cp = k.codeUnitAt(0);
        expect(cp, greaterThanOrEqualTo(0xE000));
        expect(cp, lessThanOrEqualTo(0xE03D));
      }
    });
  });

  group('WebDriverWait', () {
    test('until returns the value once the condition turns truthy', () {
      var n = 0;
      final w = WebDriverWait<int>(0, const Duration(seconds: 2),
          pollFrequency: const Duration(milliseconds: 10));
      final result = w.until<String>((_) {
        n++;
        return n >= 3 ? 'ready' : null;
      });
      expect(result, 'ready');
      expect(n, 3);
    });

    test('until throws TimeoutException when the condition never holds', () {
      final w = WebDriverWait<int>(0, const Duration(milliseconds: 60),
          pollFrequency: const Duration(milliseconds: 20));
      expect(
          () => w.until<bool>((_) => null), throwsA(isA<TimeoutException>()));
    });

    test('until ignores NoSuchElementException while polling, then succeeds',
        () {
      var n = 0;
      final w = WebDriverWait<int>(0, const Duration(seconds: 2),
          pollFrequency: const Duration(milliseconds: 10));
      final ok = w.until<bool>((_) {
        n++;
        if (n < 3) throw NoSuchElementException('not yet', 17);
        return true;
      });
      expect(ok, isTrue);
    });

    test('untilNot returns true once the condition turns falsy', () {
      var n = 0;
      final w = WebDriverWait<int>(0, const Duration(seconds: 2),
          pollFrequency: const Duration(milliseconds: 10));
      expect(w.untilNot<bool>((_) => (++n) < 3), isTrue);
    });
  });

  group('Select', () {
    FakeSelect build() => FakeSelect([
          FakeOption('o0',
              text: 'Red', attributes: {'value': 'r'}, selected: false),
          FakeOption('o1',
              text: 'Green', attributes: {'value': 'g'}, selected: false),
          FakeOption('o2',
              text: 'Blue', attributes: {'value': 'b'}, selected: false),
        ]);

    test('rejects a non-<select> element', () {
      expect(() => Select(FakeOption('x', tagName: 'div')),
          throwsA(isA<ArgumentError>()));
    });

    test('selectByValue clicks the matching option', () {
      final sel = build();
      Select(sel).selectByValue('g');
      final opts = sel.findElements(By.tagName('option')).cast<FakeOption>();
      expect(opts[1].clicks, 1);
      expect(opts[1].selected, isTrue);
      expect(opts[0].clicks, 0);
      expect(opts[2].clicks, 0);
    });

    test('selectByVisibleText picks by displayed text', () {
      final sel = build();
      Select(sel).selectByVisibleText('Blue');
      expect(
          sel.findElements(By.tagName('option')).cast<FakeOption>()[2].selected,
          isTrue);
    });

    test('selectByIndex picks by position', () {
      final sel = build();
      Select(sel).selectByIndex(0);
      expect(
          sel.findElements(By.tagName('option')).cast<FakeOption>()[0].selected,
          isTrue);
    });

    test('an absent value / out-of-range index throws NoSuchElement', () {
      expect(() => Select(build()).selectByValue('nope'),
          throwsA(isA<NoSuchElementException>()));
      expect(() => Select(build()).selectByIndex(9),
          throwsA(isA<NoSuchElementException>()));
    });

    test('an already-selected option is not clicked again', () {
      final opts = [
        FakeOption('o0',
            text: 'Red', attributes: {'value': 'r'}, selected: true),
      ];
      final sel = FakeSelect(opts);
      Select(sel).selectByValue('r');
      expect(opts[0].clicks, 0);
    });

    test('isMultiple reflects the multiple attribute', () {
      expect(Select(FakeSelect(const [])).isMultiple, isFalse);
      expect(
          Select(FakeSelect(const [], attrs: {'multiple': 'true'})).isMultiple,
          isTrue);
    });
  });

  group('Actions', () {
    test('click(element) builds a pointer move + down + up', () {
      final el = FakeOption('E1');
      final a = Actions(FakeDriver())..click(el);
      final w3c = a.toW3c();
      expect(w3c, hasLength(1));
      final pointer = w3c[0];
      expect(pointer['type'], 'pointer');
      expect(pointer['id'], 'mouse');
      expect(pointer['parameters'], {'pointerType': 'mouse'});
      final seq = pointer['actions'] as List;
      expect(seq[0]['type'], 'pointerMove');
      expect(seq[0]['origin'], {_elementKey: 'E1'});
      expect(seq[1], {'type': 'pointerDown', 'button': 0});
      expect(seq[2], {'type': 'pointerUp', 'button': 0});
    });

    test('contextClick uses button 2', () {
      final seq = (Actions(FakeDriver())..contextClick(FakeOption('E1')))
          .toW3c()[0]['actions'] as List;
      expect(seq[1], {'type': 'pointerDown', 'button': 2});
      expect(seq[2], {'type': 'pointerUp', 'button': 2});
    });

    test('doubleClick emits two down/up pairs', () {
      final seq = (Actions(FakeDriver())..doubleClick(FakeOption('E1')))
          .toW3c()[0]['actions'] as List;
      final downs = seq.where((a) => a['type'] == 'pointerDown').length;
      final ups = seq.where((a) => a['type'] == 'pointerUp').length;
      expect(downs, 2);
      expect(ups, 2);
    });

    test('dragAndDrop is hold(source) -> move(target) -> release', () {
      final src = FakeOption('S');
      final tgt = FakeOption('T');
      final seq = (Actions(FakeDriver())..dragAndDrop(src, tgt)).toW3c()[0]
          ['actions'] as List;
      expect(seq[0]['origin'], {_elementKey: 'S'});
      expect(seq[1], {'type': 'pointerDown', 'button': 0});
      expect(seq[2]['origin'], {_elementKey: 'T'});
      expect(seq.last, {'type': 'pointerUp', 'button': 0});
    });

    test('sendKeys adds a key device with down/up per char + padded pointer',
        () {
      final w3c = (Actions(FakeDriver())..sendKeys('hi')).toW3c();
      // Only the key device carries real events; the pointer stays all-pause.
      expect(w3c, hasLength(1));
      final key = w3c[0];
      expect(key['type'], 'key');
      expect(key['id'], 'keyboard');
      final seq = key['actions'] as List;
      expect(
          seq.map((a) => a['type']), ['keyDown', 'keyUp', 'keyDown', 'keyUp']);
      expect(seq[0]['value'], 'h');
      expect(seq[2]['value'], 'i');
    });

    test('keyDown+click mixes devices and keeps their tick counts equal', () {
      final el = FakeOption('E1');
      final a = Actions(FakeDriver())
        ..keyDown(Keys.shift)
        ..click(el)
        ..keyUp(Keys.shift);
      final w3c = a.toW3c();
      expect(w3c, hasLength(2));
      final pointer = w3c.firstWhere((d) => d['type'] == 'pointer');
      final key = w3c.firstWhere((d) => d['type'] == 'key');
      expect(
          (pointer['actions'] as List).length, (key['actions'] as List).length,
          reason: 'W3C requires equal device tick counts');
      expect((key['actions'] as List).first['value'], Keys.shift);
    });

    test('perform posts the built actions through the driver', () {
      final drv = FakeDriver();
      (Actions(drv)..click(FakeOption('E1'))).perform();
      expect(drv.posted, isNotNull);
      expect(drv.posted!.first['type'], 'pointer');
    });

    test('perform with no gestures posts nothing', () {
      final drv = FakeDriver();
      Actions(drv).perform();
      expect(drv.posted, isNull);
    });
  });
}
