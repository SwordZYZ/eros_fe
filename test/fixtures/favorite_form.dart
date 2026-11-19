String favoriteForm({String? category, String note = ''}) {
  final selected = category ?? '0';
  final remove = category == null
      ? ''
      : '<div><input type="radio" name="favcat" value="favdel"></div>';
  final submit = category == null ? 'Add to Favorites' : 'Apply Changes';
  final rows = List.generate(10, (i) {
    final checked = selected == '$i' ? 'checked' : '';
    return '''
      <div>
        <div><input type="radio" name="favcat" value="$i" $checked></div>
        <div></div><div>Category $i</div>
      </div>''';
  }).join();
  return '''
    <form id="galpop">
      <div><div class="nosel">$rows$remove</div><textarea>$note</textarea></div>
      <input type="submit" name="apply" value="$submit">
    </form>''';
}
