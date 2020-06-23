import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_image_add_drag_sort/flutter_image_add_drag_sort.dart';
import 'package:image_picker/image_picker.dart';

void main() => runApp(new MyApp());

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => new _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  Widget build(BuildContext context) {
    return new MaterialApp(
        theme: ThemeData(
          primarySwatch: Colors.green,
        ),
        home: new MyHomePage());
  }
}

class MyHomePage extends StatefulWidget {
  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final GlobalKey<ScaffoldState> _key = GlobalKey();
  List<ImageDataItem> imageList = [];

  @override
  Widget build(BuildContext context) {
    var imgSize = (MediaQuery.of(context).size.width - 32) / 4.0 - 2.0;
    return Scaffold(
      appBar: AppBar(
        title: Text('Image add'),
        automaticallyImplyLeading: false,
        elevation: 0.0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Text("最多可以添加9张图片, 添加图像后，长按可拖动排序。", style: TextStyle(fontSize: 13, color: const Color(0xffb0b0b0)), textAlign: TextAlign.start),
            SizedBox(height: 8.0),
            Builder(
              builder: (context) {
                return ImageAddDragContainer(
                  key: _key,
                  data: imageList,
                  maxCount: 9,
                  readOnly: false,
                  draggableMode: false,
                  itemSize: Size(imgSize, imgSize),
                  addWidget: Icon(Icons.add, size: 24, color: Colors.black38),
                  onAddImage: (uploading, onBegin) async {
                    return await doAddImage(uploading, onBegin);
                  },
                  onChanged: (items) async {
                    imageList = items;
                  },
                  onTapItem: (item, index) {
                    Scaffold.of(context).showSnackBar(SnackBar(content: Text("click item: $index, ${item.key}")));
                  },
                  builderItem: (context, key, url, type) {
                    return Container(
                      color: Colors.yellow,
                      child: url == null || url.isEmpty ? null : Image.file(File(url)),
                    );
                  },
                );
              },
            )
          ],
        ),
      ),
    );
  }

  doAddImage(List<ImageDataItem> uploading, onBegin) async {
    File image = await ImagePicker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 85,
    );
    if (image == null)
      return null;
    if (onBegin != null) await onBegin();
    await sleep(1000);  // 加个延时， 模拟网络处理
    return ImageDataItem(image.absolute.path, key: DateTime.now().millisecondsSinceEpoch.toString());
  }

  static sleep(int milliseconds) async {
    await Future.delayed(Duration(milliseconds: milliseconds));
  }

}
