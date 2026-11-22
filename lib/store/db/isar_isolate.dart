import 'dart:convert';
import 'dart:io';

import 'package:eros_fe/models/gallery_provider.dart';
import 'package:eros_fe/store/db/entity/gallery_image_task.dart';
import 'package:eros_fe/store/db/entity/gallery_task.dart';
import 'package:eros_fe/store/db/entity/tag_translat.dart';
import 'package:eros_fe/store/db/entity/tag_translate_info.dart';
import 'package:eros_fe/store/db/entity/view_history.dart';
import 'package:isar_community/isar.dart';

import 'isar.dart';

Future<void> iAddHistory(GalleryProvider galleryProvider) async {
  final gid = int.tryParse(galleryProvider.gid ?? '0') ?? 0;
  final lastViewTime = galleryProvider.lastViewTime ?? 0;
  final isar = await openIsar();
  isar.writeTxnSync(() {
    isar.viewHistorys.putSync(ViewHistory(
        gid: gid,
        lastViewTime: lastViewTime,
        galleryProviderText: jsonEncode(galleryProvider)));
  });
}

Future<void> iAddHistories(List<GalleryProvider> allHistory) async {
  final isar = await openIsar();
  final viewHistories = allHistory
      .map((e) => ViewHistory(
          gid: int.tryParse(e.gid ?? '0') ?? 0,
          lastViewTime: e.lastViewTime ?? 0,
          galleryProviderText: jsonEncode(e)))
      .toList();

  isar.writeTxnSync(() async {
    isar.viewHistorys.putAllSync(viewHistories);
  });
}

Future<List<String>> iImportTagTranslations(
  ({String directory, String filePath, String version}) input,
) async {
  final json = utf8.decode(gzip.decode(File(input.filePath).readAsBytesSync()));
  final dictionary = jsonDecode(json) as Map<String, dynamic>;
  final namespaces = <String>[];
  final translations = <TagTranslat>[];
  for (final group in dictionary['data'] as List) {
    final namespace = group['namespace'] as String;
    final data = group['data'] as Map<String, dynamic>;
    if (data.isNotEmpty) {
      namespaces.add(namespace);
    }
    for (final entry in data.entries) {
      final tag = entry.value as Map<String, dynamic>;
      translations.add(TagTranslat(
        namespace: namespace,
        key: entry.key,
        name: (tag['name'] ?? '') as String,
        intro: (tag['intro'] ?? '') as String,
        links: (tag['links'] ?? '') as String,
      ));
    }
  }
  if (translations.isEmpty) {
    throw const FormatException('Empty tag dictionary');
  }

  final isar = await openIsar(directory: input.directory);
  isar.writeTxnSync(() {
    final tags = isar.tagTranslats;
    final usage = {
      for (final tag in tags.where().lastUseTimeGreaterThan(0).findAllSync())
        (tag.key, tag.namespace): tag.lastUseTime,
    };
    tags.clearSync();
    tags.putAllSync([
      for (final tag in translations)
        if (usage[(tag.key, tag.namespace)] case final lastUseTime?)
          tag.copyWith(lastUseTime: lastUseTime)
        else
          tag,
    ]);
    isar.tagTranslateInfos.putSync(
      TagTranslateInfo(localVersion: input.version),
    );
  });
  return namespaces;
}

Future<void> iPutAllGalleryTasks(List<GalleryTask> galleryTasks) async {
  final isar = await openIsar();
  isar.writeTxnSync(() {
    isar.galleryTasks.putAllSync(galleryTasks);
  });
}

Future<void> iPutGalleryTaskIsolate((GalleryTask, bool) para) async {
  final (galleryTask, replaceOnConflict) = para;
  final isar = await openIsar();

  final existGids = isar.galleryTasks.where().gidProperty().findAllSync();
  final taskExist = existGids.contains(galleryTask.gid);

  if (replaceOnConflict) {
    isar.writeTxnSync(() {
      isar.galleryTasks.putSync(galleryTask);
    });
  } else {
    if (!taskExist) {
      isar.writeTxnSync(() {
        isar.galleryTasks.putSync(galleryTask);
      });
    }
  }
}

Future<void> iPutAllImageTask(List<GalleryImageTask> imageTasks) async {
  final isar = await openIsar();
  isar.writeTxnSync(() {
    isar.galleryImageTasks.putAllSync(imageTasks);
  });
}

Future<void> iPutImageTask(GalleryImageTask imageTask) async {
  final isar = await openIsar();
  isar.writeTxnSync(() {
    isar.galleryImageTasks.putSync(imageTask);
  });
}

Future<void> iUpdateImageTaskStatus((int, int, int) para) async {
  final (gid, ser, status) = para;
  final isar = await openIsar();
  isar.writeTxnSync(() {
    final tasks = isar.galleryImageTasks.getByGidSerSync(gid, ser);
    if (tasks != null) {
      isar.galleryImageTasks.putByGidSerSync(tasks.copyWith(status: status));
    }
  });
}

// iFinaAllImageTaskByGidAndStatus
Future<List<GalleryImageTask>> iFinaAllImageTaskByGidAndStatus(
    (int, int) para) async {
  final (gid, status) = para;
  final isar = await openIsar();
  return isar.galleryImageTasks
      .where()
      .gidEqualTo(gid)
      .filter()
      .statusEqualTo(status)
      .findAllSync();
}

// iFindImageTaskAllByGid
Future<List<GalleryImageTask>> iFindImageTaskAllByGid(int gid) async {
  final isar = await openIsar();
  return isar.galleryImageTasks
      .where()
      .gidEqualTo(gid)
      .sortBySer()
      .findAllSync();
}

// iFindImageTaskAllByGidSer
Future<GalleryImageTask?> iFindImageTaskAllByGidSer((int, int) para) async {
  final (gid, ser) = para;
  final isar = await openIsar();
  return isar.galleryImageTasks.getByGidSer(gid, ser);
}

// iFindGalleryTaskByGid
Future<GalleryTask?> iFindGalleryTaskByGid(int gid) async {
  final isar = await openIsar();
  return isar.galleryTasks.getSync(gid);
}

// iFindAllGalleryTasks
Future<List<GalleryTask>> iFindAllGalleryTasks(void _) async {
  final isar = await openIsar();
  return isar.galleryTasks.where().sortByAddTimeDesc().findAllSync();
}

// iOnDownloadComplete
Future<List<GalleryImageTask>> iOnDownloadComplete((int, int, int) para) async {
  final (gid, ser, status) = para;
  final isar = await openIsar();
  return isar.writeTxnSync(() {
    final tasks = isar.galleryImageTasks.getByGidSerSync(gid, ser);
    if (tasks != null) {
      isar.galleryImageTasks.putByGidSerSync(tasks.copyWith(status: status));
    }
    return isar.galleryImageTasks
        .where()
        .gidEqualTo(gid)
        .filter()
        .statusEqualTo(status)
        .findAllSync();
  });
}

// iUpdateGalleryTaskIsolate
Future<void> iUpdateGalleryTaskIsolate(
    (int, GalleryTask Function(GalleryTask)) para) async {
  final (gid, func) = para;
  final isar = await openIsar();

  final galleryTask = isar.galleryTasks.getSync(gid);
  if (galleryTask != null) {
    isar.writeTxnSync(() {
      final _galleryTask = func(galleryTask);
      isar.galleryTasks.putSync(_galleryTask);
    });
  }
}
