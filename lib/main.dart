import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  static const String title = 'QQ/TIM 闪照获取工具';

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: title,
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  FlutterLocalNotificationsPlugin notification;
  SharedPreferences preferences;
  Timer timer;

  Future<String> sdcard;
  bool isRunning = false;
  int id = 1;

  @override
  void initState() {
    super.initState();

    if (!Platform.isAndroid) {
      showToast('只支持 Android 平台！');
      exit(0);
    }

    notification = FlutterLocalNotificationsPlugin();
    SharedPreferences.getInstance().then((prefs) {
      preferences = prefs;
      notification.initialize(
        InitializationSettings(
          AndroidInitializationSettings('app_icon'),
          IOSInitializationSettings(),
        ),
        onSelectNotification: clickNotification,
      );

      isRunning = preferences.getBool('isRunning') ?? false;
      _toggleNotification(toRun: isRunning);

      checkPermission().then((valid) {
        if (!valid) {
          showToast('存储权限为必须权限。');
          requestPermission();
        }
        sdcard = getExternalStorageDirectory().then((value) => value.path);
      });
    });
  }

  Future<List<String>> get _localPaths async {
    var directory = await sdcard;
    return [
      '/Tim/diskcache',
      '/MobileQQ/diskcache',
      '/MobileQQ/chatpic/chatimg',
      '/Android/data/com.tencent.mobileqq/Tencent/MobileQQ/chatpic/chatimg',
    ].map((path) => directory + path);
  }

  Future<String> get _toPath async {
    var directory = await sdcard;
    return directory + '/FlashPicture/';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(MyApp.title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Tips: ',
                    textScaleFactor: 1.5,
                  ),
                  Text('1. 点击右下角按钮自动捕获闪照(5秒/次)'),
                  Text('2. 点击通知以手动捕获闪照'),
                  Text('3. 想要捕获时建议先点开闪照再返回（不要查看）'),
                  Text('4. 出现“发现加密闪照”时请重复步骤3'),
                  Text('5. 任何一次成功保存闪照都是玄学'),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          _toggleNotification();
        },
        child: Icon(isRunning ? Icons.stop : Icons.play_arrow),
      ),
    );
  }

  Future<bool> checkPermission() async {
    var status = await PermissionHandler()
        .checkPermissionStatus(PermissionGroup.storage);
    return status == PermissionStatus.granted;
  }

  Future clickNotification(String payload) async {
    switch (payload) {
      case 'saveResult':
        getFlashPicture();
        break;
      default:
        openImage(payload);
        break;
    }
  }

  Future<void> copyFlashPicture(String path, String picture) async {
    var dir = Directory(await _toPath);
    if (!await dir.exists()) {
      await dir.create();
    }

    var result = (await _toPath) + picture + '.png';
    if (await File(result).exists()) {
      picture = '';
      return;
    }

    // Remove encrypted flash pictures
    // Not that this is executed after file.exists, which ignores fetch flash picture now
    if (await isEncrypted(path)) {
      try {
        await File(path).delete();
      } finally {
        await showToast('发现加密闪照，已移除。');
      }
      return;
    }

    await File(path).copy(result);
    await showToast('发现新闪照: ' + picture);
    _showResultNotification(picture + '.png');
  }

  Future<void> getFlashPicture() async {
    // 1. Check whether the cache folder exists
    var paths = await _validLocalPath();
    if (paths.isEmpty) {
      await showToast('缓存目录不存在！');
      _toggleNotification();
      return;
    }

    // 2. Get files in cache folder
    paths.forEach((path) {
      List<FileSystemEntity> list;
      try {
        list = Directory(path)
            .listSync(recursive: true)
            .where((item) => item.uri.pathSegments.last.endsWith('fp'))
            .toList();
      } catch (e) {
        return;
      }

      for (var item in list) {
        copyFlashPicture(item.path, item.uri.pathSegments.last);
      }
    });
  }

  Future<bool> isEncrypted(String path) async {
    var bytes = await File(path).readAsBytes();
    // ENCRYPT:
    return bytes[0] == 0x45 &&
        bytes[1] == 0x4E &&
        bytes[2] == 0x43 &&
        bytes[3] == 0x52 &&
        bytes[4] == 0x59 &&
        bytes[5] == 0x50 &&
        bytes[6] == 0x54 &&
        bytes[7] == 0x3A;
  }

  void requestPermission() async {
    Map<PermissionGroup, PermissionStatus> status =
        await PermissionHandler().requestPermissions([PermissionGroup.storage]);
    if (status[PermissionGroup.storage] != PermissionStatus.granted) {
      exit(0);
    }
  }

  Future<void> showToast(String message) async {
    await Fluttertoast.showToast(
        msg: message,
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
        timeInSecForIos: 1,
        textColor: Colors.white,
        fontSize: 12.0);
  }

  Future<List<String>> _validLocalPath() async =>
      (await _localPaths).where((p) => Directory(p).existsSync()).toList();

  Future<String> openImage(String name) async {
    var path = await _toPath;
    return OpenFile.open(path + name);
  }

  void _toggleNotification({toRun = false}) {
    if (!toRun) {
      if (isRunning) {
        notification.cancel(0);
        timer.cancel();
        _toggleRunning();
      }
      return;
    }

    var androidSpec = AndroidNotificationDetails(
      'fpc',
      MyApp.title,
      '捕获 QQ 或 TIM 的闪照',
      importance: Importance.Max,
      priority: Priority.Max,
      autoCancel: false,
      ongoing: true,
      style: AndroidNotificationStyle.Default,
      styleInformation: DefaultStyleInformation(true, true),
    );
    var platformSpec = NotificationDetails(
      androidSpec,
      IOSNotificationDetails(),
    );

    timer = Timer.periodic(Duration(seconds: 5), (timer) => getFlashPicture());

    notification.show(
      0,
      MyApp.title,
      '自动捕获闪照中，点击该通知以手动捕获。',
      platformSpec,
      payload: 'saveResult',
    );
    _toggleRunning();
  }

  void _showResultNotification(String name) async {
    var androidSpec = AndroidNotificationDetails(
      'fpc',
      MyApp.title,
      '捕获 QQ 或 TIM 的闪照',
      importance: Importance.Max,
      priority: Priority.Max,
      style: AndroidNotificationStyle.BigPicture,
      styleInformation: BigPictureStyleInformation(
        (await _toPath) + name,
        BitmapSource.FilePath,
        largeIcon: (await _toPath) + name,
        largeIconBitmapSource: BitmapSource.FilePath,
        contentTitle: '闪照获取成功！点击打开~',
        htmlFormatContentTitle: true,
        summaryText: name,
        htmlFormatSummaryText: true,
      ),
    );
    var platformSpec = NotificationDetails(
      androidSpec,
      IOSNotificationDetails(),
    );
    notification.show(
      id++,
      'QQ/TIM 闪照获取工具',
      '',
      platformSpec,
      payload: name,
    );
  }

  void _toggleRunning() async {
    await preferences.setBool('isRunning', !isRunning);
    setState(() {
      isRunning = !isRunning;
    });
  }
}
