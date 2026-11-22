import 'package:eros_fe/common/controller/tag_trans_controller.dart';
import 'package:eros_fe/common/service/ehsetting_service.dart';
import 'package:eros_fe/index.dart';
import 'package:eros_fe/pages/setting/setting_items/selector_Item.dart';
import 'package:eros_fe/widget/cupertino/window_control_insets.dart';
import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';
import 'package:sliver_tools/sliver_tools.dart';

class TagTranslatePage extends StatelessWidget {
  const TagTranslatePage({super.key});

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground,
      navigationBar: CupertinoNavigationBar(
        middle: const Text('标签翻译'),
      ).withWindowAwareBackButton(),
      child: const CustomScrollView(
        slivers: [
          SliverSafeArea(sliver: ListViewTagTranslate()),
        ],
      ),
    );
  }
}

class ListViewTagTranslate extends StatelessWidget {
  const ListViewTagTranslate({super.key});

  EhSettingService get _ehSettingService => Get.find();

  TagTransController get transController => Get.find();

  Future<void> _handleTagTranslatChanged(bool newValue) async {
    _ehSettingService.isTagTranslate = newValue;
    if (newValue) {
      await _updateTranslations();
    }
  }

  void _handleTagTranslatCDNChanged(bool newValue) {
    _ehSettingService.enableTagTranslateCDN = newValue;
  }

  Future<void> _updateTranslations({bool force = false}) async {
    final bool updated;
    try {
      updated = await transController.updateTranslations(force: force);
    } catch (error, stackTrace) {
      logger.e('更新标签翻译失败', error: error, stackTrace: stackTrace);
      showToast('更新失败');
      return;
    }
    if (updated) {
      showToast('更新完成');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiSliver(children: [
      SliverCupertinoListSection.listInsetGrouped(children: [
        // _handleTagTranslatChanged switch
        EhCupertinoListTile(
          title: const Text('启用标签翻译'),
          subtitle: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Obx(() {
                final progress = transController.downloadProgress;
                if (progress == null) {
                  return const SizedBox.shrink();
                }
                if (progress.total <= 0) {
                  return const Text('下载中…');
                }
                final percent = (100 * progress.received / progress.total)
                    .clamp(0, 100)
                    .toStringAsFixed(1);
                return Text('下载进度：$percent%');
              }),
              Obx(() => Text(
                    '当前版本:${_ehSettingService.tagTranslatVer.value}',
                    maxLines: 3,
                  )),
            ],
          ),
          trailing: Obx(() {
            return Row(
              children: [
                CupertinoButton(
                  padding: const EdgeInsets.all(0),
                  onPressed: () => _updateTranslations(force: true),
                  child: const Icon(CupertinoIcons.refresh),
                ),
                CupertinoSwitch(
                  value: _ehSettingService.isTagTranslate,
                  onChanged: _handleTagTranslatChanged,
                ),
              ],
            );
          }),
        ),

        Obx(() {
          return AnimatedCrossFade(
            alignment: Alignment.center,
            crossFadeState: _ehSettingService.isTagTranslate
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstCurve: Curves.easeIn,
            secondCurve: Curves.easeOut,
            duration: const Duration(milliseconds: 200),
            firstChild: const SizedBox(),
            secondChild: _buildTagIntroImgLvItem(context),
          );
        }),

        // enableTagTranslateCDN switch
        EhCupertinoListTile(
          title: const Text('加速下载数据'),
          subtitle: const Text('使用CDN加速下载数据'),
          trailing: Obx(() {
            return CupertinoSwitch(
              value: _ehSettingService.enableTagTranslateCDN,
              onChanged: _handleTagTranslatCDNChanged,
            );
          }),
        ),

        _buildTagTranslateDataUpdateModeItem(context),
      ]),
    ]);
  }
}

/// 标签介绍图片切换
Widget _buildTagIntroImgLvItem(BuildContext context) {
  const String title = '标签介绍图片';
  final EhSettingService ehSettingService = Get.find();

  final Map<TagIntroImgLv, String> descMap = <TagIntroImgLv, String>{
    TagIntroImgLv.disable: '禁用',
    TagIntroImgLv.nonh: '隐藏H图片',
    TagIntroImgLv.r18: '隐藏引起不适的图片',
    TagIntroImgLv.r18g: '全部显示',
  };

  return Obx(() {
    return SelectorCupertinoListTile<TagIntroImgLv>(
      title: title,
      actionMap: descMap,
      initVal: ehSettingService.tagIntroImgLv.value,
      onValueChanged: (val) => ehSettingService.tagIntroImgLv.value = val,
    );
  });
}

/// 自动更新策略切换
Widget _buildTagTranslateDataUpdateModeItem(BuildContext context) {
  const String title = '自动更新策略';
  final EhSettingService ehSettingService = Get.find();

  final Map<TagTranslateDataUpdateMode, String> modeMap =
      <TagTranslateDataUpdateMode, String>{
    TagTranslateDataUpdateMode.manual: '手动更新',
    TagTranslateDataUpdateMode.everyStartApp: '启动App时更新',
  };

  return Obx(() {
    return SelectorCupertinoListTile<TagTranslateDataUpdateMode>(
      title: title,
      actionMap: modeMap,
      initVal: ehSettingService.tagTranslateDataUpdateMode,
      onValueChanged: (val) =>
          ehSettingService.tagTranslateDataUpdateMode = val,
    );
  });
}
