import 'dart:convert';
import 'dart:io';

import 'favorite_form.dart';

enum FavoriteWrite { accept, reject, disconnect, httpError }

class FavoriteServer {
  FavoriteServer._(this._server) {
    _server.listen(_handle);
  }

  static Future<FavoriteServer> start() async =>
      FavoriteServer._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));

  final HttpServer _server;
  String get origin => 'http://127.0.0.1:${_server.port}';

  String? category;
  String note = '';
  FavoriteWrite response = FavoriteWrite.accept;
  int reads = 0;
  final writes = <Map<String, String>>[];
  bool showLoginPage = false;
  String? cover;

  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    final reply = request.response;
    final coverUrl = cover;
    if (coverUrl != null && request.uri.path.startsWith('/g/')) {
      final id = int.tryParse(category ?? '');
      final favorite = id == null
          ? '<span id="fav"></span><a id="favoritelink">Add to Favorites</a>'
          : '<span id="fav"><div style="background-position:0px -${2 + 19 * id}px;"></div></span>'
                '<a id="favoritelink">Category $id</a>';
      reply.headers.contentType = ContentType.html;
      reply.write('''
        <h1 id="gn">Favorite test gallery</h1>
        <div id="gd1"><div style="background-image: url($coverUrl)"></div></div>
        <div id="gdc"><div>misc</div></div>
        $favorite
      ''');
      await reply.close();
      return;
    }
    if (request.uri.path != '/gallerypopups.php' ||
        request.uri.queryParameters['act'] != 'addfav') {
      reply.statusCode = HttpStatus.notFound;
      await reply.close();
      return;
    }
    reply.headers.contentType = ContentType.html;
    reply.headers.set(HttpHeaders.cacheControlHeader, 'max-age=3600');
    if (request.method == 'POST') {
      final body = await utf8.decoder.bind(request).join();
      final form = Uri.splitQueryString(body);
      writes.add(form);
      if (response == FavoriteWrite.disconnect) {
        (await reply.detachSocket(writeHeaders: false)).destroy();
        return;
      }
      if (response == FavoriteWrite.httpError) {
        reply.statusCode = HttpStatus.forbidden;
      } else if (response == FavoriteWrite.accept &&
          request.headers.contentType?.mimeType ==
              'application/x-www-form-urlencoded' &&
          form['update'] == '1' &&
          form['apply']?.isNotEmpty == true) {
        category = form['favcat'] == 'favdel' ? null : form['favcat'];
        note = form['favnote'] ?? '';
      } else {
        reply.write('Favorites update refused');
      }
    } else {
      reads++;
      reply.write(
        showLoginPage
            ? '<form>Log in</form>'
            : favoriteForm(
                category: category,
                note: const HtmlEscape().convert(note),
              ),
      );
    }
    await reply.close();
  }
}
