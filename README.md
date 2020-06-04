# flutter_image_add_drag_sort

[![pub package](https://img.shields.io/pub/v/flutter_image_add_drag_sort.svg)](https://pub.dartlang.org/packages/flutter_image_add_drag_sort)
![GitHub](https://img.shields.io/github/license/yangyxd/flutter_image_add_drag_sort.svg)
[![GitHub stars](https://img.shields.io/github/stars/yangyxd/flutter_image_add_drag_sort.svg?style=social&label=Stars)](https://github.com/yangyxd/flutter_image_add_drag_sort)

Flutter Image add drag sort, Image add drag sort, support click event, delete, add, long press drag sort, support video fixed as the first.

> Supported  Platforms
> * Android
> * IOS

![image](https://github.com/yangyxd/flutter_image_add_drag_sort/blob/master/raw/001.gif)

## LICENSE 

### MIT License

## How to Use

```yaml
# add this line to your dependencies
flutter_picker:
  git: git://github.com/yangyxd/flutter_image_add_drag_sort.git
```
### or
```dart
import 'package:flutter_picker/flutter_image_add_drag_sort.dart';
```

## example

```dart
  List<ImageDataItem> imageList = [];

  ...

  ImageAddDragContainer(
      key: _key,  // GlobalKey()
      data: imageList,
      maxCount: 9,
      readOnly: false,
      draggableMode: false,
      itemSize: Size(imgSize, imgSize),
      addWidget: Icon(Icons.add, size: 24, color: Colors.black38),
      onAddImage: (onBegin) async {
        // add image 
        return await doAddImage(onBegin);
      },
      onChanged: (items) async {
        imageList = items;
      },
      onTapItem: (item, index) {
        Scaffold.of(context).showSnackBar(SnackBar(content: Text("click item: $index, ${item.key}")));
      },
      builderItem: (context, key, url, type) {
        // custom builder item
        return Container(
          color: Colors.yellow,
          child: url == null || url.isEmpty ? null : Image.file(File(url)),
        );
      },
  )

```

