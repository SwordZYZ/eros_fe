import 'package:eros_fe/models/base/eh_models.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' show parse;

FavAdd parserAddFavPage(String? response) {
  // 解析响应信息dom
  final Document document = parse(response);

  final List<Favcat> favList = <Favcat>[];

  String? select;
  final List<Element> favcats = document.querySelectorAll(
    '#galpop > div > div.nosel > div',
  );
  for (final Element fav in favcats) {
    final List<Element> divs = fav.querySelectorAll('div');
    final input = fav.querySelector('input[name="favcat"]');
    final favId = input?.attributes['value']?.trim();
    if (favId == null || !RegExp(r'^[0-9]$').hasMatch(favId)) {
      continue;
    }
    if (divs.length < 3) {
      throw const FormatException('Invalid favorite category');
    }
    if (input!.attributes.containsKey('checked')) {
      if (select != null) {
        throw const FormatException('Multiple favorite categories selected');
      }
      select = favId;
    }
    final String favTitle = divs[2].text.trim();
    favList.add(Favcat(favId: favId, favTitle: favTitle));
  }

  if (favList.map((fav) => fav.favId).toSet().length != 10) {
    throw const FormatException('Favorite form missing from response');
  }

  // The add form can preselect a category even when the gallery is not saved.
  final removeOption = document.querySelector(
    '#galpop input[name="favcat"][value="favdel"]',
  );
  final submit = document.querySelector(
    '#galpop input[type="submit"], #galpop button[type="submit"]',
  );
  final action = submit?.attributes['value'] ?? submit?.text;
  if (removeOption == null &&
      action?.trim() == 'Add to Favorites') {
    select = null;
  }

  final textareaElm = document.querySelector('#galpop textarea');
  final note = textareaElm?.text.trim();

  return FavAdd(
    favcats: favList,
    usedNoteSlots: '1',
    maxNoteSlots: '100',
    favNote: note,
    selectFavcat: select,
  );
}
