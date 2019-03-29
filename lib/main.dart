import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';

FlutterLocalNotificationsPlugin notification;

void main() {
  notification = FlutterLocalNotificationsPlugin();
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'QQ/TIM 闪照获取工具',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: MyHomePage(title: 'QQ/TIM 闪照获取工具'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  MyHomePage({Key key, this.title}) : super(key: key);

  final String title;

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  bool isQQ = true;

  @override
  void initState() {
    super.initState();
    var initializationSettingsAndroid =
        new AndroidInitializationSettings('app_icon');
    var initializationSettingsIOS = new IOSInitializationSettings();
    var initializationSettings = new InitializationSettings(
        initializationSettingsAndroid, initializationSettingsIOS);
    notification.initialize(initializationSettings,
        onSelectNotification: getFlashPicture);

    checkPermission().then((valid) {
      if (!valid) {
        requestPermission();
      }
    });
  }

  Future<bool> checkPermission() async {
    var status = await PermissionHandler()
        .checkPermissionStatus(PermissionGroup.storage);
    return status == PermissionStatus.granted;
  }

  requestPermission() async {
    await PermissionHandler().requestPermissions([PermissionGroup.storage]);
  }

  void _toggleQQTim() {
    setState(() {
      isQQ = !isQQ;
    });
  }

  Future<String> get _localPath async {
    final directory = await getExternalStorageDirectory();
    return directory.path +
        '/tencent/' +
        (isQQ ? 'MobileQQ' : 'Tim') +
        '/diskcache';
  }

  Future<bool> _localPathExists() async => Directory(await _localPath).exists();

  void _showNotification() async {
    var exists = await _localPathExists();
    debugPrint(await _localPath);
    if (!exists) {
      debugPrint('Not Exist!');
      return;
    }

    var androidPlatformChannelSpecifics = new AndroidNotificationDetails(
        'fpc', 'FlashPicture Capturer', 'Capture flash picture of QQ or TIM.',
        importance: Importance.Max, priority: Priority.Max, autoCancel: false);
    var iOSPlatformChannelSpecifics = new IOSNotificationDetails();
    var platformChannelSpecifics = new NotificationDetails(
        androidPlatformChannelSpecifics, iOSPlatformChannelSpecifics);
    notification.show(
        0, "QQ/TIM 闪照获取工具", "当需要保存闪照时，点击该通知。", platformChannelSpecifics);
    _localPath;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              '目前只支持QQ',
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showNotification,
        tooltip: '显示通知',
        child: Icon(Icons.play_arrow),
      ),
    );
  }

  Future getFlashPicture(String payload) async {
    await requestPermission();
    var path = await _localPath;
    List<FileSystemEntity> list;
    try {
      list = Directory(path).listSync(recursive: true);
    } catch (e) {
      debugPrint(e.toString());
      return;
    }
    if (list.length > 0) {
      list.sort((a, b) => (a.statSync().modified.millisecondsSinceEpoch <
              b.statSync().modified.millisecondsSinceEpoch)
          ? 1
          : -1);

      for (var item in list) {
        if (item.uri.pathSegments.last.endsWith("_fp")) {
          debugPrint('发现闪照: ' + item.path);
          debugPrint('修改时间: ' + item.statSync().modified.toString());
          break;
        }
      }
    }
  }
}
