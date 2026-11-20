import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:eros_fe/common/controller/user_controller.dart';
import 'package:eros_fe/common/global.dart';
import 'package:eros_fe/common/service/ehsetting_service.dart';
import 'package:eros_fe/common/service/locale_service.dart';
import 'package:eros_fe/network/api.dart';
import 'package:eros_fe/network/app_dio/pdio.dart';
import 'package:eros_fe/network/request.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'fixtures/favorite_server.dart';

class _Settings extends EhSettingService {
  // Skip preferences and plugin initialization in this networking test.
  @override
  // ignore: must_call_super
  void onInit() {}
}

class _User extends UserController {
  // Skip persistent profile setup for the synthetic test user.
  @override
  // ignore: must_call_super
  void onInit() {}
}

class _Binding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}

void main() {
  _Binding();
  late FavoriteServer server;
  final previousConfig = globalDioConfig;

  setUp(() async {
    Get.testMode = true;
    server = await FavoriteServer.start();
    Get.put(LocaleService());
    Get.put<EhSettingService>(_Settings());
    Get.put<UserController>(_User());
    Api.cacheOption = CacheOptions(store: MemCacheStore());
    globalDioConfig = DioHttpConfig(baseUrl: server.origin);
  });

  tearDown(() async {
    await server.close();
    globalDioConfig = previousConfig;
    Get.reset();
  });

  test('confirms add, move and removal against fresh server state', () async {
    expect((await galleryGetFavorite('1', 'token')).selectFavcat, isNull);
    await galleryAddFavorite('1', 'token', favcat: '0', favnote: 'a & 中文');
    expect(server.category, '0');
    expect(server.note, 'a & 中文');
    await galleryAddFavorite('1', 'token', favcat: '9');
    expect(server.category, '9');
    await galleryAddFavorite('1', 'token');
    expect(server.category, isNull);
    expect(server.reads, 4);
  });

  test('HTTP 200 without the requested change fails', () async {
    server.category = '1';
    server.response = FavoriteWrite.reject;
    await expectLater(
      galleryAddFavorite('1', 'token', favcat: '2'),
      throwsException,
    );
    await expectLater(galleryAddFavorite('1', 'token'), throwsException);
    expect(server.category, '1');
  });

  test('HTTP errors and transport failures skip confirmation', () async {
    for (final mode in [FavoriteWrite.httpError, FavoriteWrite.disconnect]) {
      server.response = mode;
      await expectLater(
        galleryAddFavorite('1', 'token', favcat: '2'),
        throwsException,
      );
    }
    expect(server.reads, 0);
    expect(server.category, isNull);
  });

  test('login HTML cannot confirm a removal', () async {
    server.showLoginPage = true;
    await expectLater(galleryAddFavorite('1', 'token'), throwsFormatException);
  });
}
