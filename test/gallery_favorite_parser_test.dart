import 'package:eros_fe/common/parser/gallery_fav_parser.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/favorite_form.dart';

void main() {
  test('reads a checked category even when the checked attribute is empty', () {
    final form = parserAddFavPage(favoriteForm(category: '0', note: '中文'));
    expect(form.selectFavcat, '0');
    expect(
      form.favcats.map((fav) => fav.favId),
      List.generate(10, (i) => '$i'),
    );
    expect(form.favNote, '中文');
  });

  test('a default radio selection in the add form is not a saved favorite', () {
    expect(favoriteForm(), contains('value="0" checked'));
    expect(parserAddFavPage(favoriteForm()).selectFavcat, isNull);
  });

  test('a login page cannot confirm removal', () {
    expect(
      () => parserAddFavPage('<form><input name="password"></form>'),
      throwsFormatException,
    );
  });
}
