import 'dart:async';
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
Timer timer;

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
  bool isTaskRunning = false;
  bool isQQ = true;
  int id = 1;

  Future<List<String>> get _localPaths async {
    final directory = await getExternalStorageDirectory();
    final base = directory.path + '/tencent/';
    List<String> paths = [];
    if (isQQ) {
      paths.add(base + 'MobileQQ/chatpic/chatimg');
    }
    paths.add(base + (isQQ ? 'MobileQQ' : 'Tim') + '/diskcache');
    return paths;
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
                  Text('2. 长按右下角按钮启用自动捕获模式(5秒/次)'),
                  Text('3. 点击通知以手动捕获闪照'),
                  Text('4. 想要捕获时建议先点开闪照再返回（不要查看）'),
                  Text('5. 出现“发现加密闪照”时请重复步骤4'),
                  Text('6. 任何一次成功保存闪照都是玄学'),
                ],
              ),
            ),
            FlatButton(
              child: Text('切换为 ' + (isQQ ? 'TIM' : 'QQ')),
              onPressed: () {
                if (isRunning) {
                  _showNotification();
                }
                _toggleQQTim();
              },
            ),
            Text(''),
          ],
        ),
      ),
      floatingActionButton: InkWell(
        splashColor: Colors.blue,
        onLongPress: () {
          isTaskRunning = true;
          _showNotification();
        },
        child: FloatingActionButton(
          onPressed: () {
            isTaskRunning = false;
            _showNotification();
          },
          child: Icon(isRunning
              ? isTaskRunning ? Icons.pause : Icons.stop
              : Icons.play_arrow),
        ),
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

  Future<void> copyFlashPicture(String path, String picture) async {
    var dir = Directory(await _toPath);
    if (!await dir.exists()) {
      await dir.create();
    }

    debugPrint(File(path).hashCode.toString());

    if (await isEncrypted(path)) {
      await File(path).delete();
      await showToast('发现加密闪照，已移除。');
      return;
    }

    var result = (await _toPath) + picture + '.png';
    if (await File(result).exists()) {
      picture = '';
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
      if (isTaskRunning) {
        isTaskRunning = false;
        _showNotification();
      }
      return;
    }

    // 2. Get files in cache folder
    var pictureCount = 0;
    paths.forEach((path) {
      List<FileSystemEntity> list;
      try {
        list = Directory(path)
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
          // await showToast('发现闪照: ' + item.uri.pathSegments.last);
          // await showToast('修改时间: ' + item.statSync().modified.toString());
          pictureCount++;
          var picture = item.uri.pathSegments.last;
          debugPrint(picture);
          copyFlashPicture(item.path, picture);
        }
      }
    });

    // FlashPicture Not Found
    if (pictureCount == 0 && !isTaskRunning) {
      await showToast('未发现新的闪照！');
    }
  }

  @override
  void initState() {
    super.initState();

    if (!Platform.isAndroid) {
      showToast('只支持 Android 平台！');
      exit(0);
    }

    notification.initialize(
      InitializationSettings(
        AndroidInitializationSettings('app_icon'),
        IOSInitializationSettings(),
      ),
      onSelectNotification: clickNotification,
    );

    isRunning = preferences.getBool('isRunning') ?? false;
    isTaskRunning =
        isRunning ? (preferences.getBool('isTaskRunning') ?? false) : false;
    isQQ = preferences.getBool('isQQ') ?? true;

    if (isRunning) {
      isRunning = false;
      _showNotification();
    }

    checkPermission().then((valid) {
      if (!valid) {
        showDialog(
            context: context,
            builder: (context) {
              return AlertDialog(
                title: Text('隐私条款'),
                content: Text('本应用通过读取/写入内置存储实现闪照的发现与保存，请允许存储权限。'),
                actions: <Widget>[
                  FlatButton(
                    child: Text('确定'),
                    onPressed: () {
                      requestPermission(context);
                    },
                  )
                ],
              );
            });
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

  void requestPermission(context) async {
    Map<PermissionGroup, PermissionStatus> status =
        await PermissionHandler().requestPermissions([PermissionGroup.storage]);
    if (status[PermissionGroup.storage] != PermissionStatus.granted) {
      exit(0);
    } else {
      Navigator.of(context).pop();
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

  Future _openImage(String name) =>
      _toPath.then((String path) => OpenFile.open(path + name));

  void _showNotification() {
    if (isRunning) {
      notification.cancel(0);
      if (isTaskRunning) timer.cancel();
      _toggleRunning();
      return;
    }

    var androidPlatformChannelSpecifics = AndroidNotificationDetails(
      'fpc',
      'QQ/TIM 闪照获取工具',
      '捕获 QQ 或 TIM 的闪照',
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

    if (isTaskRunning) {
      timer =
          Timer.periodic(Duration(seconds: 5), (timer) => getFlashPicture());
      getFlashPicture();
    }

    notification.show(
      0,
      'QQ/TIM 闪照获取工具',
      isTaskRunning ? '自动捕获闪照中，也可以点击该通知手动触发。' : '当需要保存闪照时，点击该通知。',
      platformChannelSpecifics,
      payload: 'saveResult',
    );
    _toggleRunning();
  }

  void _showResultNotification(String name) async {
    var androidPlatformChannelSpecifics = AndroidNotificationDetails(
      'fpc',
      'QQ/TIM 闪照获取工具',
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
    await preferences.setBool('isQQ', !isQQ);
    setState(() {
      isQQ = !isQQ;
    });
  }

  void _toggleRunning() async {
    await preferences.setBool('isRunning', !isRunning);
    await preferences.setBool('isTaskRunning', isTaskRunning);
    setState(() {
      isRunning = !isRunning;
    });
  }
}
