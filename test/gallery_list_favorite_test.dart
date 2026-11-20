import 'package:eros_fe/common/parser/gallery_list_parser.dart';
import 'package:flutter_test/flutter_test.dart';

String _galleryRow(String marker) => '''
<table><tbody><tr>
  <td class="gl1c glcat"><div>Manga</div></td>
  <td class="gl2c"> <div><div><img style="height:120px;width:80px"></div></div><div>$marker<div class="ir" style="0px 0px"><div></div><div><div></div><div>4 pages</div></div></div></div><div><div></div><div class="ir"></div></div></td>
  <td class="gl3c glname">
    <a href="https://fixture.invalid/g/42/favorite/"><div class="glink">Test gallery</div></a>
  </td>
  <td class="gl4c glhide"><div>Test</div><div>4 pages</div></td>
</tr></tbody></table>
''';

void main() {
  test('reads a favorite from a nested date marker with an RGBA background', () {
    final gallery = parseGalleryList(
      _galleryRow('''
        <section><div id="posted_42" title="Category 2"
          style="background-color: rgba(240, 160, 0, 0.4)">2026-11-20 00:00</div></section>
      '''),
    ).gallerys!.single;
    expect(gallery.favTitle, 'Category 2');
    expect(gallery.favcat, '2');
  });

  test('favorites list accepts a full hex border color with whitespace', () {
    final gallery = parseGalleryListOfFav(
      _galleryRow('''
        <div id="posted_42" title="Category 6"
          style="border-color: #44BBFF">2026-11-20 00:00</div>
      '''),
    ).gallerys!.single;
    expect(gallery.favTitle, 'Category 6');
    expect(gallery.favcat, '6');
  });

  test('an ordinary dated cell without a favorite title stays unmarked', () {
    final gallery = parseGalleryList(
      _galleryRow('''
        <div id="posted_42" style="border-color:#000;">2026-11-20 00:00</div>
      '''),
    ).gallerys!.single;
    expect(gallery.favcat, isEmpty);
  });
}
