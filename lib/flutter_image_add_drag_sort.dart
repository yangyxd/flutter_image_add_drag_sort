library flutter_image_add_drag_sort;

import 'dart:io';
import 'package:flutter/material.dart';
import 'draggable/draggable_container.dart';

/// [ImageAddDragView] image data
class ImageDataItem {
  /// Image key. If an image is uploaded or added successfully, you need to specify a key, which can be the file name, time stamp, or key stored in the cloud
  final String key;
  /// image url or file path
  final String url;
  /// Video snapshot URL, if type = 1, this attribute will be used first to display
  final String fps;
  /// image type: 0 image， 1 video
  final int type;

  const ImageDataItem(this.url, {this.key, this.fps, this.type = 0});
}

/// Add images and display as grid, support long drag sorting, deletion and click events
class ImageAddDragContainer extends StatefulWidget {
  const ImageAddDragContainer({
    /// Key must have, otherwise there will be exceptions
    @required Key key,
    @required this.data,
    this.maxCount = 9,
    this.fit,
    this.color,
    this.itemSize = const Size(65, 65),
    this.margin = const EdgeInsets.all(5),
    this.readOnly = false,
    this.draggableMode = false,
    this.willPopScope = false,
    this.addWidget,
    this.slotDecoration,
    this.dragDecoration,
    this.deleteButton,
    this.deleteButtonPosition = const Offset(-8, -8),
    this.builderItem,
    this.onAddImage,
    this.onChanged,
    this.onDelete,
    this.onTapItem,
  }): assert(maxCount != null), super(key: key);

  /// image data list
  final List<ImageDataItem> data;

  /// image display clipping method
  final BoxFit fit;

  /// How many images can be added at most ?
  final int maxCount;

  /// Add image event, return image data.
  ///
  /// The onBegin callback is used to display the wait animation when starting to add or upload an image
  final Future<ImageDataItem> Function(Function([int index, bool fixed, bool deletable]) onBegin) onAddImage;

  /// Image list change event
  final Future<void> Function(List<ImageDataItem> items) onChanged;

  /// Image deletion event (before deletion), return false to cancel deletion
  final Future<bool> Function(ImageDataItem item, int index) onDelete;

  /// Image click event
  final Function(ImageDataItem item, int index) onTapItem;

  /// Custom add button, default use Icon(Icons.add).
  final Widget addWidget;

  /// image item, grid size
  final Size itemSize;

  /// image item margin
  final EdgeInsets margin;

  /// Read only or not
  final bool readOnly;

  /// Edit mode, delete allowed
  final bool draggableMode;

  /// Whether to block the return key and exit editing mode when in editing mode
  final bool willPopScope;

  /// background color
  final Color color;

  final BoxDecoration slotDecoration, dragDecoration;

  /// Custom delete button, generally displayed in the upper right corner of imageItem
  final Widget deleteButton;
  /// Specify delete button offset
  final Offset deleteButtonPosition;

  /// custom builder image item
  final BuilderImageItem builderItem;

  @override
  State<StatefulWidget> createState() => _ImageAddDragContainerState();
}

typedef BuilderImageItem = Widget Function(BuildContext context, String key, String url, int type);

class _ImageAddDragContainerState extends State<ImageAddDragContainer> {
  final items = <DraggableItem>[];
  final GlobalKey<DraggableContainerState> _containerKey = GlobalKey();
  _MyItem _addButton;
  var imageList = <ImageDataItem>[];

  @override
  void initState() {
    super.initState();

    imageList.addAll(widget.data);
    _addButton = _MyItem(url: null, deletable: false, addWidget: widget.addWidget, widget: widget, onTap: () async {

      final items = _containerKey.currentState.items;
      final buttonIndex = items.indexOf(_addButton);
      final nullIndex = items.length >= widget.maxCount ? -1 : items.length;
      if (buttonIndex > -1) {
        var item = _MyItem(url: '', deletable: false, fixed: false, widget: widget);
        var isUploadBegin = false;
        int index;
        var newIndex;
        var image = await widget.onAddImage(([_index, fixed, deletable]) async {
          index = _index;
          if (fixed != null) item.fixed = fixed;
          if (deletable != null) item.deletable = deletable;
          newIndex = buttonIndex;
          var existIndex = index != null && index >= 0 && (index < nullIndex || (items.length == widget.maxCount));
          if (existIndex)
            newIndex = index;
          if (nullIndex > -1) {
            await _containerKey.currentState.addSlot(triggerEvent: false);
            await _containerKey.currentState.insertOfIndex(newIndex, item, triggerEvent: false, force: true);
          } else {
            _containerKey.currentState.removeIndex(buttonIndex, triggerEvent: false);
            await _containerKey.currentState.insertOfIndex(newIndex, item, force: true, triggerEvent: false);
          }
          isUploadBegin = true;
        });
        if (!isUploadBegin)
          return;
        if (image != null) {
          item.key = image.key;
          item.url = image.url;
          item.type = image.type;
        }
        if (item.key == null || item.key.isEmpty) {
          _containerKey.currentState.removeIndex(newIndex, triggerEvent: false);
          if (nullIndex > -1)
            await _containerKey.currentState.popSlot();
        } else {
          updateItemChild(item);
          await _containerKey.currentState.insteadOfIndex(newIndex, item, force: true);
        }
      }

    });

    if (imageList.isNotEmpty) {
      updateItems();
      return;
    }

    if (widget.onAddImage != null) {
      items.addAll([
        _addButton
      ]);
    }
  }

  updateItemChild(_MyItem item) {
   item.deletable = true;

    var _onTap = () {
      var index = imageList.indexWhere((element) => element.key == item.key && element.type == item.type);
      if (widget.onTapItem != null && index >= 0)
        widget.onTapItem(imageList[index], index);
    };

    if (widget.builderItem == null) {
      item.child = ImageItemView(key: Key("_img:" + item.url),
          url: item.url,
          fps: item.fps,
          type: item.type,
          fit: widget.fit,
          onTap: _onTap
      );
    } else {
      Widget _view = widget.builderItem(context, item.key, item.url, item.type);
      item.child = widget.onTapItem == null ? _view : GestureDetector(
          child: _view,
          onTap: _onTap
      );
    }
  }

  int indexOfImageList(_MyItem item, [int defaultIndex = -1]) {
    for (int i = 0; i < imageList.length; i++) {
      if (imageList[i].type == item.type && imageList[i].url == item.url)
        return i;
    }
    return defaultIndex;
  }

  @override
  void didUpdateWidget(ImageAddDragContainer oldWidget) {
    super.didUpdateWidget(oldWidget);
    var _len = imageList.length;
    if (_len < widget.maxCount) _len++;
    updateItems();
  }

  min(int a, int b) {
    if (a < b) return a;
    return b;
  }

  updateItems() async {
    // await _containerKey.currentState.clear(triggerEvent: false);
    if (_addButton != null) {
      _addButton.addWidget = widget.addWidget;
      _addButton.child = ImageItemView(url: _addButton.url,
          type: _addButton.type,
          addWidget: widget.addWidget,
          onTap: _addButton.onTap);
    }
    this.items.clear();
    var i = 0;
    for (var item in imageList) {
      var v = _MyItem(key: item.key, type: item.type, url: item.url, fps: item.fps, fixed: item.type == 1, widget: widget);
      updateItemChild(v);
      this.items.add(v);
    }
    if (imageList.length < widget.maxCount && widget.onAddImage != null)
      this.items.add(_addButton);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableContainer(
      key: _containerKey,
      items: items,
      draggableMode: widget.draggableMode,
      editMode: true,
      autoReorder: false,
      readOnly: widget.readOnly,
      willPopScope: widget.willPopScope,
      color: widget.color,
      slotDecoration: widget.slotDecoration ?? BoxDecoration(border: Border.all(width: 2, color: Theme.of(context).primaryColor.withAlpha(100))),
      dragDecoration: widget.dragDecoration ?? BoxDecoration(boxShadow: [BoxShadow(color: Colors.black, blurRadius: 10)]),
      slotMargin: widget.margin,
      slotSize: widget.itemSize,
      deleteButton: widget.deleteButton ?? Container(
        width: 18,
        height: 18,
        child: Icon(Icons.close, size: 12.0, color: Colors.white),
        decoration: BoxDecoration(
          color: Colors.redAccent.withAlpha(50),
          borderRadius: BorderRadius.circular(16.0),
        ),
      ),
      deleteButtonPosition: widget.deleteButtonPosition ?? const Offset(0, 0),
      onChanged: (_items) async {
        imageList.clear();
        for (var _item in _items) {
          if (_item != null && _item is _MyItem && _item.url != null)
            imageList.add(ImageDataItem(_item.url, key: _item.key, fps: _item.fps, type: _item.type));
        }
        if (widget.onChanged != null)
          widget.onChanged(imageList);
      },
      onBeforeDelete: (index, item) async {
        if (widget.onDelete != null)
          return await widget.onDelete(imageList[index], index);
        else
          return true;
      },
      onAfterDelete: (index, item) async {
        var buttonIndex = _containerKey.currentState.items.indexOf(_addButton);
        if (buttonIndex < 0) {
          _containerKey.currentState.insteadOfIndex(_containerKey.currentState.items.length - 1, _addButton);
        } else {
          _containerKey.currentState.moveTo(buttonIndex, buttonIndex - 1);
          _containerKey.currentState.popSlot();
        }
      },
      onDraggableModeChanged: (bool draggableMode) {

      },
    );
  }
}

class _MyItem extends DraggableItem {
  _MyItem({this.key, this.type = 0, this.url, this.fps, bool fixed = true, bool deletable = false, this.addWidget, this.onTap,
    @required ImageAddDragContainer widget}): super(fixed: fixed, deletable: deletable) {
    this.child = ImageItemView(keyStr: key, url: url, type: type, addWidget: addWidget, onTap: onTap, builder: widget.builderItem);
  }

  Widget child, addWidget;
  final Function onTap;

  /// 0 图像， 1 视频
  int type;
  String key;
  String fps;
  @override
  String toString() => key;
  String url;
}


class ImageItemView extends StatefulWidget {
  const ImageItemView({Key key, this.keyStr, this.url, this.fps, this.type, this.addWidget, this.fit, this.builder, this.onTap}) : super(key: key);
  final String keyStr;
  final String url;
  final String fps;
  /// 0 图像， 1 视频
  final int type;
  final Widget addWidget;
  final BoxFit fit;
  final BuilderImageItem builder;
  final VoidCallback onTap;

  @override
  State<StatefulWidget> createState() => _ImageItemViewState();

  bool get isEmpty => url == null;
}

class _ImageItemViewState extends State<ImageItemView> {

  @override
  void initState() {
    super.initState();
  }

  @override
  void didUpdateWidget(ImageItemView oldWidget) {
    super.didUpdateWidget(oldWidget);
  }

  bool empty(String v) {
    return v == null || v.isEmpty;
  }

  @override
  Widget build(BuildContext context) {
    Widget img;
    if (!widget.isEmpty && widget.url.isNotEmpty) {
      String url = widget.type == 1 && !empty(widget.fps) ? widget.fps : widget.url;
      if (widget.builder != null)
        img = widget.builder(context, widget.keyStr, url, widget.type);
      else {
        if (url != null && url.startsWith("http"))
          img = Image.network(url,  fit: widget.fit == null ? BoxFit.cover : widget.fit);
        else
          img = Image.file(File(url), fit: widget.fit == null ? BoxFit.cover : widget.fit);
      }
      if (widget.type == 1) {
        img = Stack(
          alignment: Alignment.center,
          children: <Widget>[
            SizedBox(child: img, width: double.infinity, height: double.infinity),
            Container(
                child: Icon(Icons.play_arrow, size: 20, color: Colors.white),
                padding: const EdgeInsets.fromLTRB(11, 9, 9, 9),
                alignment: Alignment.center,
                width: 32.0,
                height: 32.0,
                decoration: BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                )
            )
          ],
        );
      }
    }
    return GestureDetector(
        child: Container(
            child: !widget.isEmpty ?
            (
                widget.url.isEmpty ?
                Container(padding: const EdgeInsets.all(16.0), child: CircularProgressIndicator(strokeWidth: 1.0)) :
                img
            ) :
            widget.addWidget == null ? Icon(Icons.add) : widget.addWidget,
            decoration: BoxDecoration(
              color: const Color(0xfff7f7f7),
              // border: Border.all(color: Styles.lineBtnBorderColor, width: 0.5),
            )
        ),
        onTap: widget.onTap
    );
  }
}
