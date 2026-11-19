import 'package:eros_fe/common/service/theme_service.dart';
import 'package:eros_fe/generated/l10n.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:get/get.dart';

import '../controller/login_controller.dart';

class LoginPage extends GetView<LoginController> {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    final placeholderStyle = kTextStyle.copyWith(
      fontWeight: FontWeight.w400,
      color: CupertinoColors.placeholderText,
    );
    final useWindowInsets =
        !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.iOS &&
        (ModalRoute.of(context)?.canPop ?? false);

    return CupertinoPageScaffold(
      backgroundColor: !ehTheme.isDarkMode
          ? CupertinoColors.secondarySystemBackground
          : null,
      navigationBar: CupertinoNavigationBar(
        middle: Text(L10n.of(context).user_login),
        padding: useWindowInsets ? const EdgeInsetsDirectional.only(end: 16) : null,
        leading: useWindowInsets ? const _WindowAwareBackButton() : null,
      ),
      child: SafeArea(
        bottom: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 500),
            child: SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: 50),
                  const FaIcon(
                    FontAwesomeIcons.circleUser,
                    size: 120,
                    color: CupertinoColors.activeBlue,
                  ),
                  const SizedBox(height: 40),
                  CupertinoFormSection.insetGrouped(
                    backgroundColor: Colors.transparent,
                    margin: const EdgeInsets.fromLTRB(16, 10, 16, 30),
                    children: [
                      CupertinoTextFormFieldRow(
                        controller: controller.usernameController,
                        style: kTextStyle,
                        placeholderStyle: placeholderStyle,
                        prefix: Row(
                          children: [
                            const FaIcon(
                              FontAwesomeIcons.user,
                              size: 20,
                            ).paddingOnly(right: 12.0),
                            Text(L10n.of(context).user_name),
                          ],
                        ),
                        // placeholder: L10n.of(context).pls_i_username,
                        textAlign: TextAlign.right,
                        onEditingComplete: () {
                          FocusScope.of(context)
                              .requestFocus(controller.nodePwd);
                        },
                      ),
                      GetBuilder<LoginController>(
                        builder: (logic) {
                          return CupertinoTextFormFieldRow(
                            controller: controller.passwdController,
                            style: kTextStyle,
                            placeholderStyle: placeholderStyle,
                            prefix: Row(
                              children: [
                                GestureDetector(
                                  onTap: logic.switchObscure,
                                  child: FaIcon(
                                    logic.obscurePasswd
                                        ? FontAwesomeIcons.eyeSlash
                                        : FontAwesomeIcons.eye,
                                    size: 20,
                                  ).paddingOnly(right: 12.0),
                                ),
                                Text(L10n.of(context).passwd),
                              ],
                            ),
                            // placeholder: L10n.of(context).pls_i_passwd,
                            textAlign: TextAlign.right,
                            obscureText: logic.obscurePasswd,
                            focusNode: logic.nodePwd,
                          );
                        },
                      ),
                    ],
                  ),
                  SizedBox(
                    height: 50,
                    child: GetBuilder<LoginController>(
                      builder: (logic) {
                        return CupertinoButton.filled(
                          // color: CupertinoColors.activeBlue,
                          onPressed:
                              logic.loadingLogin ? null : logic.pressLogin,
                          child: logic.loadingLogin
                              ? const CupertinoActivityIndicator()
                              : Text(
                                  L10n.of(context).login,
                                  style: const TextStyle(height: 1.2),
                                ),
                        );
                      },
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      // web登陆
                      if (GetPlatform.isMobile)
                        CupertinoButton(
                          minSize: 50,
                          padding: const EdgeInsets.all(20),
                          onPressed: controller.handOnWeblogin,
                          child: const Column(
                            children: [
                              FaIcon(
                                FontAwesomeIcons.earthAmericas,
                                size: 30,
                              ),
                              Text('Web',
                                  textScaler: const TextScaler.linear(0.8)),
                            ],
                          ),
                        ),
                      // cookie登陆
                      CupertinoButton(
                        minSize: 50,
                        padding: const EdgeInsets.all(20),
                        onPressed: controller.hanOnCookieLogin,
                        child: const Column(
                          children: [
                            FaIcon(
                              FontAwesomeIcons.cookieBite,
                              size: 30,
                            ),
                            Text('Cookie',
                                textScaler: const TextScaler.linear(0.8)),
                          ],
                        ),
                      ),
                    ],
                  ).paddingSymmetric(vertical: 30),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WindowAwareBackButton extends StatefulWidget {
  const _WindowAwareBackButton();

  @override
  State<_WindowAwareBackButton> createState() => _WindowAwareBackButtonState();
}

class _WindowAwareBackButtonState extends State<_WindowAwareBackButton> {
  static const _channel = MethodChannel('eros_fe/window_layout');
  late Future<Map<String, double>?> _insets;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Requery UIKit when iPadOS resizes the Flutter window.
    MediaQuery.sizeOf(context);
    MediaQuery.viewPaddingOf(context);
    _insets = _channel.invokeMapMethod<String, double>('windowControlInsets');
  }

  @override
  Widget build(BuildContext context) {
    final edge = Directionality.of(context) == TextDirection.ltr
        ? 'left'
        : 'right';
    return FutureBuilder<Map<String, double>?>(
      future: _insets,
      builder: (context, snapshot) => Padding(
        padding: EdgeInsetsDirectional.only(start: snapshot.data?[edge] ?? 0),
        child: const CupertinoNavigationBarBackButton(),
      ),
    );
  }
}
