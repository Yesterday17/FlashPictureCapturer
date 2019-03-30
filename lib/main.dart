import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  notification = FlutterLocalNotificationsPlugin();
  SharedPreferences.getInstance().then((prefs) {
    preferences = prefs;
    runApp(MyApp());
  });
}

FlutterLocalNotificationsPlugin notification;
SharedPreferences preferences;

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
  final String title;

  MyHomePage({Key key, this.title}) : super(key: key);

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  bool isRunning = false;
  bool isQQ = true;
  int id = 1;
  String picture = '';

  Future<String> get _localPath async {
    final directory = await getExternalStorageDirectory();
    return directory.path +
        '/tencent/' +
        (isQQ ? 'MobileQQ' : 'Tim') +
        '/diskcache';
  }

  Future<String> get _toPath async {
    final directory = await getExternalStorageDirectory();
    return directory.path + '/FlashPicture/';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
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
                  Text('1. 点击右下角按钮打开通知'),
                  Text('2. 在想要保存闪照时点击通知即可'),
                  Text('3. 出现“发现加密闪照”时请重试'),
                  Text('4. 出现“未发现新的闪照”时请尝试接收一张别的闪照'),
                  Text('5. 任何一次成功保存闪照都是玄学'),
                ],
              ),
            ),
            FlatButton(
              child: Text('切换为 ' + (isQQ ? 'TIM' : 'QQ')),
              onPressed: _toggleQQTim,
            ),
            Text(''),
            Text(''),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showNotification,
        tooltip: '显示通知',
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
        _openImage(payload);
        break;
    }
  }

  Future copyFlashPicture(String path) async {
    var dir = Directory(await _toPath);
    if (!dir.existsSync()) {
      dir.createSync();
    }

    debugPrint(File(path).hashCode.toString());

    if (await isEncrypted(path)) {
      File(path).deleteSync();
      showToast('发现加密闪照，已移除。\n请尝试重新获得图片！');
      return;
    }

    var result = (await _toPath) + picture + '.png';
    if (File(result).existsSync()) {
      picture = '';
      return;
    }

    File(path).copySync(result);
    showToast('发现新闪照: ' + picture);
    _showResultNotification(picture + ".png");
  }

  Future getFlashPicture() async {
    // 1. Check whether the cache folder exists
    var exists = await _localPathExists();
    if (!exists) {
      showToast('缓存目录不存在！');
      return;
    }

    // 2. Get files in cache folder
    List<FileSystemEntity> list;
    try {
      list = Directory(await _localPath)
          .listSync(recursive: true)
          .where((item) => item.uri.pathSegments.last.endsWith('fp'))
          .toList();
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
        // showToast('发现闪照: ' + item.uri.pathSegments.last);
        // showToast('修改时间: ' + item.statSync().modified.toString());
        picture = item.uri.pathSegments.last;
        await copyFlashPicture(item.path);
      }
    }

    // FlashPicture Not Found
    if (picture == '') {
      showToast('未发现新的闪照！');
    }
    picture = ''; // Reset picture
  }

  @override
  void initState() {
    super.initState();

    if (!Platform.isAndroid) {
      showToast('只支持 Android 平台！');
      exit(0);
    }

    var initializationSettings = InitializationSettings(
      AndroidInitializationSettings('app_icon'),
      IOSInitializationSettings(),
    );
    notification.initialize(
      initializationSettings,
      onSelectNotification: clickNotification,
    );

    isRunning = preferences.getBool("isRunning") ?? false;
    isQQ = preferences.getBool("isQQ") ?? true;

    if (isRunning) {
      isRunning = false;
      _showNotification();
    }
    checkPermission().then((valid) {
      if (!valid) {
        showToast('存储权限为必须权限。');
        requestPermission();
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

  void showToast(String message) {
    Fluttertoast.showToast(
      msg: message,
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.BOTTOM,
      timeInSecForIos: 3,
      backgroundColor: Colors.blueGrey,
      textColor: Colors.white,
      fontSize: 12.0,
    );
  }

  Future<bool> _localPathExists() async => Directory(await _localPath).exists();

  Future _openImage(String name) =>
      _toPath.then((String path) => OpenFile.open(path + name));

  void _showNotification() {
    if (isRunning) {
      notification.cancel(0);
      _toggleRunning();
      return;
    }

    var androidPlatformChannelSpecifics = AndroidNotificationDetails(
      'fpc',
      'FlashPicture Capturer',
      'Capture flash picture of QQ or TIM.',
      importance: Importance.Max,
      priority: Priority.Max,
      autoCancel: false,
      ongoing: true,
      style: AndroidNotificationStyle.Default,
      styleInformation: DefaultStyleInformation(true, true),
    );
    var platformChannelSpecifics = NotificationDetails(
      androidPlatformChannelSpecifics,
      IOSNotificationDetails(),
    );
    notification.show(
      0,
      'QQ/TIM 闪照获取工具',
      '当需要保存闪照时，点击该通知。',
      platformChannelSpecifics,
      payload: "saveResult",
    );
    _toggleRunning();
  }

  void _showResultNotification(String name) async {
    var androidPlatformChannelSpecifics = AndroidNotificationDetails(
      'fpc',
      'FlashPicture Capturer',
      'Capture flash picture of QQ or TIM.',
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
    var platformChannelSpecifics = NotificationDetails(
      androidPlatformChannelSpecifics,
      IOSNotificationDetails(),
    );
    notification.show(
      id++,
      'QQ/TIM 闪照获取工具',
      '',
      platformChannelSpecifics,
      payload: name,
    );
  }

  void _toggleQQTim() async {
    await preferences.setBool("isQQ", !isQQ);
    setState(() {
      isQQ = !isQQ;
    });
  }

  void _toggleRunning() async {
    await preferences.setBool("isRunning", !isRunning);
    setState(() {
      isRunning = !isRunning;
    });
  }
}
