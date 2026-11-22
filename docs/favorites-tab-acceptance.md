# 收藏分组栏验收清单

分支 `codex/ipad-tab-indicator-alignment`。顶栏位置在 iPad 真机 `579` 核验，菜单跳组在 `579` 复现、在 `580` 复测通过。

## 1. 收藏顶栏与画廊对齐

- [x] 保持同一横屏方向和分栏宽度，在画廊页和收藏页各看一次顶部分组栏。收藏页的蓝条与遮罩下边框较旧版同步上抬 **6 pt**，在 `579` 截图中与画廊页逐像素对齐。分组文字保持原来的高度。[画廊截图](../artifacts/ipad-tab-indicator/initial-579-tabs.png) · [收藏截图](../artifacts/ipad-tab-indicator/favorite-579-tabs.png)
- [ ] 打开「滚动时隐藏顶部栏」，纵向滚动收藏列表再返回顶部。检查折叠和展开时蓝条仍贴合文字，下边框随遮罩移动，列表首项和下拉刷新区域与顶栏衔接正常。这一项尚未单独真机复测。

### 改动文件

| 文件 | Review 重点 |
| --- | --- |
| [constants.dart](../lib/pages/tab/view/constants.dart#L12) | 画廊和收藏共用 iOS 顶栏的 6 pt 收紧量、分组栏高度和页头高度。 |
| [favorite_tabbar_page.dart · 页头](../lib/pages/tab/view/tabbar/favorite_tabbar_page.dart#L43) · [分组栏](../lib/pages/tab/view/tabbar/favorite_tabbar_page.dart#L296) | 展开和折叠高度采用共享值，遮罩和蓝条同步上移，标签加顶部补偿以保持文字位置。 |
| [favorite_sub_page.dart](../lib/pages/tab/view/tabbar/favorite_sub_page.dart#L71) | 列表和刷新区域的顶部留白跟随页头高度。 |
| [custom_tabbar_page.dart · 页头](../lib/pages/tab/view/tabbar/custom_tabbar_page.dart#L55) · [分组栏](../lib/pages/tab/view/tabbar/custom_tabbar_page.dart#L325) · [custom_sub_page.dart](../lib/pages/tab/view/tabbar/custom_sub_page.dart#L89) | 画廊使用同一组常量，沿用原有的高度和留白。 |

## 2. 点收藏标签后从菜单跳到末组

- [x] 登录后打开收藏页并缩窄左栏，确保末组起初在可视区外。点顶部 `Favorites 0`，手指不碰正文，直接从三横杠菜单选末组「本地收藏」。
- [x] `579` 复现。旧标签 `Favorites 0` 仍为蓝色，末组和蓝条未滚入视野。[复现截图](../artifacts/ipad-tab-indicator/favorite-jump-before-579-tabs.png)
- [x] `580` 按同样顺序复测。正文切到「本地收藏」，标签栏自动滚到末组，末组文字变蓝且蓝条对齐，旧组取消选中。[复测截图](../artifacts/ipad-tab-indicator/favorite-jump-after-580-tabs.png)

### 改动文件与回归测试

- [favorite_tabbar_page.dart · 菜单跳转](../lib/pages/tab/view/tabbar/favorite_tabbar_page.dart#L392) 校验菜单结果、分组索引和分页控制器状态，再恢复标签栏自动滚动并跳页。分页回调会同步选中文字和标签栏位置。[分页回调](../lib/pages/tab/view/tabbar/favorite_tabbar_page.dart#L140)
- [link_scroll_bar_test.dart · 菜单跳组回归](../test/widgets/link_scroll_bar_test.dart#L121) 用实际收藏分组栏触发菜单，验证末组滚入视野、选中文字切换及蓝条对齐。旧实现失败，修复后全部 **23 项 Flutter 测试**通过。

截图和运行日志保存在本地 `artifacts/ipad-tab-indicator/`，该目录由 Git 忽略。
