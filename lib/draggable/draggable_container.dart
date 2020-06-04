library flutter_image_add_drag_sort;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';

class LoopCheck {
  LoopCheck._();

  bool _stop = false;
  Duration _step;

  factory LoopCheck.check({int stepMilliSeconds = 100}) {
    var check = LoopCheck._();
    check._step = Duration(microseconds: stepMilliSeconds);
    return check;
  }

  Future<void> start() async {
    while (!_stop) {
      // print('$_stop');
      await Future.delayed(_step);
    }
    return Future.value();
  }

  void stop() {
    _stop = true;
  }
}

class DraggableItem {
  final Widget child;
  bool fixed;
  bool deletable;

  DraggableItem({@required this.child, this.fixed: false, this.deletable: true});
}

abstract class DraggableContainerEvent {
  onPanStart(DragStartDetails details);

  onPanUpdate(DragUpdateDetails details);

  onPanEnd(details);
}

mixin DraggableContainerEventMixin<T extends StatefulWidget> on State<T> implements DraggableContainerEvent {}

abstract class DraggableItemsEvent {
//  _deleteFromWidget(DraggableItemWidget widget);

  _deleteFromKey(GlobalKey<DraggableItemWidgetState> key);
}

mixin StageItemsEventMixin<T extends StatefulWidget> on State<T> implements DraggableItemsEvent {}

class DraggableContainer<T extends DraggableItem> extends StatefulWidget {
  final Size slotSize;

  final EdgeInsets slotMargin;

  final BoxDecoration slotDecoration, dragDecoration;
  final Function(List<T> items) onChanged;
  final Function(bool mode) onDraggableModeChanged;
  final Future<bool> Function(int index, T item) onBeforeDelete;
  final Future<void> Function(int index, T item) onAfterDelete;
  final Function onDragEnd;
  final bool draggableMode, editMode, autoReorder;
  final Offset deleteButtonPosition;
  final Duration animateDuration;
  final bool allWayUseLongPress;
  final List<T> items;
  final Widget deleteButton;
  final bool readOnly;
  final bool willPopScope;
  final Color color;

  DraggableContainer({
    Key key,
    @required this.items,
    this.deleteButton,
    this.slotSize = const Size(100, 100),
    this.slotMargin,
    this.slotDecoration,
    this.dragDecoration,
    this.autoReorder: true,
    this.editMode: true,
    this.readOnly: false,
    this.willPopScope: true,

    /// events
    this.onChanged,
    this.onDraggableModeChanged,
    this.onBeforeDelete,
    this.onAfterDelete,
    this.onDragEnd,

    /// Enter draggable mode as soon as possible
    this.draggableMode: false,

    /// When in draggable mode,
    /// still use LongPress events to drag the children widget
    this.allWayUseLongPress: false,

    /// The duration for the children widget position transition animation
    this.animateDuration: const Duration(milliseconds: 200),
    this.deleteButtonPosition: const Offset(0, 0),
    this.color,
  }) : super(key: key) {
    if (items == null || items.length == 0) {
      throw Exception('The items parameter is undeinfed or empty');
    }
  }

  @override
  DraggableContainerState createState() => DraggableContainerState<T>();
}

class DraggableContainerState<T extends DraggableItem>
    extends State<DraggableContainer>
    with DraggableContainerEventMixin, StageItemsEventMixin {
  final GlobalKey _containerKey = GlobalKey();
  final Map<DraggableSlot, GlobalKey<DraggableItemWidgetState<T>>>
  relationship = {};
  final List<DraggableItemWidget> layers = [];
  final List<GlobalKey> _dragBeforeList = [];
  final Map<Type, GestureRecognizerFactory> gestures = {};

  Widget deleteButton;
  bool _draggableMode = false;
  GlobalKey<DraggableItemWidgetState> pickUp;
  DraggableSlot toSlot;
  Offset longPressPosition;
  GestureRecognizerFactory _longPressRecognizer, _draggableItemRecognizer;
  double _maxHeight = 0;
  bool autoReorder = true;

  List<T> get items => List.from(
      relationship.values.map((globalKey) => globalKey?.currentState?.item));

  get draggableMode => _draggableMode;

  set draggableMode(bool value) {
    // print('draggableMode $value');
    _draggableMode = value;
    _setGestures();
    _updateChildren();
    if (widget.onDraggableModeChanged != null)
      widget.onDraggableModeChanged(value);
  }

  @override
  void initState() {
    super.initState();
    deleteButton = widget.deleteButton;
    autoReorder = widget.autoReorder;
    _draggableMode = widget.draggableMode && !widget.readOnly;
    _init();
  }

  @override
  void didUpdateWidget(DraggableContainer<DraggableItem> oldWidget) {
    super.didUpdateWidget(oldWidget);
    var last = _draggableMode;
    _draggableMode = widget.draggableMode && !widget.readOnly;
    if (last != _draggableMode) {
      _setGestures();
      _updateChildren();
    }
  }

  void _init() {
    if (deleteButton == null)
      deleteButton = Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
        child: Icon(
          Icons.clear,
          size: 14,
          color: Colors.white,
        ),
      );

    gestures[LongPressGestureRecognizer] = _longPressRecognizer =
        GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
                () => LongPressGestureRecognizer(),
                (LongPressGestureRecognizer instance) {
              instance
                ..onLongPressStart = onLongPressStart
                ..onLongPressMoveUpdate = onLongPressMoveUpdate
                ..onLongPressEnd = onLongPressEnd;
            });

    /// unused
    _draggableItemRecognizer =
        GestureRecognizerFactoryWithHandlers<DraggableItemRecognizer>(
                () => DraggableItemRecognizer(containerState: this),
                (DraggableItemRecognizer instance) {
              instance
                ..isHitItem = isDraggingItem
                ..isDraggingItem = () {
                  return pickUp != null;
                }
                ..onPanStart = onPanStart
                ..onPanUpdate = onPanUpdate
                ..onPanEnd = onPanEnd;
            });

    WidgetsBinding.instance
        .addPostFrameCallback((_) => _initItems(widget.items));
  }

  void _createItemWidget(DraggableSlot slot, T item) {
    if (item == null) {
      relationship[slot] = null;
      //relationship.remove(slot);
    } else {
      final GlobalKey<DraggableItemWidgetState<T>> key = GlobalKey();
      final widget = DraggableItemWidget<T>(
        key: key,
        stage: this,
        item: item,
        width: this.widget.slotSize.width,
        height: this.widget.slotSize.height,
        decoration: item == null ? null : this.widget.dragDecoration,
        deleteButton: this.deleteButton,
        deleteButtonPosition: this.widget.deleteButtonPosition,
        position: slot.position,
        editMode: this.widget.editMode,
        allowDrag: _draggableMode,
        animateDuration: this.widget.animateDuration,
      );
      layers.add(widget);
      relationship[slot] = key;
    }
  }

  bool addItem(T item, {bool triggerEvent: true}) {
    if (item == null) return false;
    final entries = relationship.entries;
    for (var i = 0; i < entries.length; i++) {
      final kv = entries.elementAt(i);
      if (kv.value == null) {
        _createItemWidget(kv.key, item);
        setState(() {});
        if (triggerEvent) _triggerOnChanged();
        return true;
      }
    }
    return false;
  }

  bool hasItem(T item) {
    return relationship.values
        .map((key) => key?.currentState?.item)
        .toList()
        .indexOf(item) >
        -1;
  }

  void _initItems(List<T> items, [bool last = false]) {
    // print('initItems');
    if (!last) {
      relationship.clear();
      layers.clear();
    }
    final RenderBox renderBoxRed =
    _containerKey.currentContext.findRenderObject();
    final size = renderBoxRed.size;
    // print('size $size');
    EdgeInsets margin = widget.slotMargin ?? EdgeInsets.all(0);
    double x = margin.left, y = margin.top;
    for (var i = 0; i < items.length; i++) {
      var isNullItem = false;
      if (!last || i == items.length - 1) {
        final item = items[i];
        if (item != null || i == items.length - 1) {
          final Offset position = Offset(x, y),
              maxPosition =
              Offset(x + widget.slotSize.width, y + widget.slotSize.height);
          final slot = DraggableSlot(
            position: position,
            width: widget.slotSize.width,
            height: widget.slotSize.height,
            // decoration: item == null ? null : widget.slotDecoration,
            maxPosition: maxPosition,
            event: this,
          );
          _createItemWidget(slot, item);
        } else
          isNullItem = true;
      }
      // print('width:${size.width}, x:$x, y:$y');
      if (!isNullItem) {
        x += widget.slotSize.width + margin.right;
        if ((x + widget.slotSize.width + margin.right) > size.width) {
          x = margin.left;
          y += widget.slotSize.height + margin.bottom + margin.top;
        } else if (i == (items.length - 1)) {
          y += widget.slotSize.height + margin.bottom;
        }
      } else {
        if (i == (items.length - 1)) {
          y += widget.slotSize.height + margin.bottom;
        }
      }
    }
    _maxHeight = y;
    // print('_maxHeight $_maxHeight');
    _setGestures();
    setState(() {});
  }

  bool removeIndex(int index, {bool triggerEvent: true}) {
    if (index < 0 || index >= relationship.length) return false;
    final entries = relationship.entries;
    var result = false;
    for (var i = 0; i < entries.length; i++) {
      if (i < index) continue;
      if (i == index) {
        final kv = entries.elementAt(i);
        if (kv.value == null) return false;
        relationship[kv.key] = null;
        layers.remove(kv.value?.currentWidget);
        result = true;
      } else {
        moveTo(i, i - 1, triggerEvent: false, force: true);
      }
    }
    if (result) {
      if (autoReorder) reorder();
      setState(() {});
      if (triggerEvent) _triggerOnChanged();
    }
    return result;
  }

  bool removeItem(T item, {bool triggerEvent: true}) {
    final entries = relationship.entries;
    for (var kv in entries) {
      if (kv.value?.currentState?.item == item) {
        layers.remove(kv.value.currentWidget);
        relationship[kv.key] = null;
        if (autoReorder) reorder();
        setState(() {});
        if (triggerEvent) _triggerOnChanged();
        return true;
      }
    }
    return false;
  }

  clear({bool triggerEvent: true}) {
    final entries = relationship.entries;
    for (var i = entries.length - 1; i >= 0; i--) {
      final kv = entries.elementAt(i);
      if (kv.value == null) return false;
      relationship[kv.key] = null;
      layers.remove(kv.value?.currentWidget);
    }
    if (autoReorder) reorder();
    setState(() {});
    if (triggerEvent) _triggerOnChanged();
  }

  Future<void> _wait() async {
    final loop = LoopCheck.check();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      loop.stop();
    });
    await loop.start();
  }

  Future<void> addSlot({T item, bool triggerEvent: true}) async {
    final items = this.items;
    items.add(item);
    _initItems(items, true);
    await _wait();
    if (autoReorder) reorder();
    if (triggerEvent) _triggerOnChanged();
  }

  Future<void> addSlots(int count, {bool triggerEvent: true}) async {
    final res = this.items;
    res.addAll(List.generate(count, (i) => null));
    _initItems(res);
    await _wait();
    if (triggerEvent) _triggerOnChanged();
  }

  Future<T> popSlot({bool triggerEvent: true}) async {
    final items = this.items;
    final last = items.last;
    items.removeAt(items.length - 1);
    _initItems(items);
    await _wait();
    if (triggerEvent) _triggerOnChanged();
    return last;
  }

  Future<bool> insteadOfIndex(int index, T item,
      {bool triggerEvent: true, bool force: false}) async {
    final slots = relationship.keys;
    if (index < 0 || slots.length <= index) return false;
    final slot = slots.elementAt(index);
    if (!force && relationship[slot]?.currentState?.item?.deletable == false)
      return false;
    layers.remove(relationship[slot]?.currentWidget);
    _createItemWidget(slot, item);
    await _wait();
    if (autoReorder) reorder();
    if (triggerEvent) _triggerOnChanged();
    setState(() {});
    return true;
  }

  Future<bool> insertOfIndex(int index, T item,
      {bool triggerEvent: true, bool force: false}) async {
    final slots = relationship.keys;
    if (index < 0 || slots.length <= index) return false;
    for (var i = slots.length - 1; i > index; i--) {
      if (i == slots.length - 1) {
        final kv = relationship.entries.elementAt(i);
        if (kv.value != null) {
          relationship[kv.key] = null;
          layers.remove(kv.value?.currentWidget);
        }
      }
      moveTo(i - 1, i, triggerEvent: false, force: force);
    }
    final slot = slots.elementAt(index);
    if (!force && relationship[slot]?.currentState?.item?.deletable == false)
      return false;

    layers.remove(relationship[slot]?.currentWidget);
    _createItemWidget(slot, item);
    await _wait();
    if (autoReorder) reorder();
    if (triggerEvent) _triggerOnChanged();
    setState(() {});
    return true;
  }

  bool moveTo(int from, int to, {bool triggerEvent: true, bool force: false}) {
    final slots = relationship.keys;
    if (from == to) return false;
    if (from < 0 || slots.length <= from) return false;
    if (to < 0 || slots.length <= to) return false;
    final fromSlot = slots.elementAt(from), toSlot = slots.elementAt(to);
    if (relationship[fromSlot] == null) return false;
    if (!force &&
        relationship[toSlot]?.currentState?.item?.deletable == false) {
      return false;
    }
    final kv = relationship.entries.elementAt(to);
    layers.remove(kv.value?.currentWidget);
    relationship[toSlot] = relationship[fromSlot];
    relationship[toSlot]?.currentState?.position = toSlot.position;
    relationship[fromSlot] = null;

    if (triggerEvent) _triggerOnChanged();
    return true;
  }

  T getItem(int index) {
    return relationship.values.elementAt(index)?.currentState?.item;
  }

  Future<bool> _deleteFromKey(GlobalKey<DraggableItemWidgetState> key) async {
    if (relationship.containsValue(key) == false) return false;

    final index = relationship.values.toList().indexOf(key);
    var _item = key?.currentState?.item;
    if (this.widget.onBeforeDelete != null) {
      bool isDelete =
      await this.widget.onBeforeDelete(index, _item);
      if (!isDelete) return false;
    }
    final kv = relationship.entries.elementAt(index);
    relationship[kv.key] = null;
    // if (autoReorder)
      reorder();
    setState(() {});
    layers.remove(kv.value?.currentWidget);
    if (widget.onAfterDelete != null)
      await this.widget.onAfterDelete(index, _item);
    _triggerOnChanged();
    return true;
  }

  reorder({int start: 0, int end: -1}) {
    var entries = relationship.entries;
    if (end == -1 || end > relationship.length) end = relationship.length;
    for (var i = start; i < end; i++) {
      final entry = entries.elementAt(i);
      final slot = entry.key;
      final item = entry.value;
      if (item == null) {
        final pair = findNextDraggableItem(start: i, end: end);
        if (pair == null) {
          break;
        } else {
          final nextSlot = pair.key, nextItem = pair.value;
          relationship[slot] = nextItem;
          if (nextItem != pickUp)
            nextItem.currentState.position = slot.position;
          relationship[nextSlot] = null;
        }
      }
    }
  }

  MapEntry<DraggableSlot, GlobalKey<DraggableItemWidgetState>>
  findNextDraggableItem({start: 0, end: -1}) {
    if (end == -1) end = relationship.length;

    var res =
    relationship.entries.toList().getRange(start, end).firstWhere((pair) {
      return pair.value?.currentState?.item?.fixed == false;
    }, orElse: () => null);

    return res;
  }

  _triggerOnChanged() {
    if (widget.onChanged != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onChanged(relationship.keys
            .map((key) => relationship[key]?.currentState?.item)
            .toList());
      });
    }
  }

  DraggableSlot findSlot(Offset position) {
    final keys = relationship.keys.toList();
    for (var i = 0; i < keys.length; i++) {
      final DraggableSlot slot = keys[i];
      if (slot.position <= position && slot.maxPosition >= position) {
        return slot;
      }
    }
    return null;
  }

  int startDown = 0;
  bool waitPanMove = false;

  @override
  onPanStart(DragStartDetails details) {
    if (!_draggableMode) return;
    final DraggableSlot slot = findSlot(details.localPosition);
    final key = relationship[slot];
    if (key == null ||
        key.currentState?.item == null ||
        key.currentState?.item?.fixed == true) return;
    pickUp = key;
    pickUp.currentState.active = true;
    layers.remove(pickUp.currentWidget);
    layers.add(pickUp.currentWidget);
    toSlot = slot;
    _dragBeforeList.addAll(relationship.values);
    setState(() {});
  }

  var temp;
  var moveChanged = 0;

  @override
  onPanUpdate(DragUpdateDetails details) {
    // print('onPanUpdate ${details.delta}');
    if (pickUp != null) {
      // 移动抓起的item
      pickUp.currentState.position += details.delta;
      final slot = findSlot(details.localPosition);
      if (slot != null && temp != slot) {
        temp = slot;
        moveChanged++;
        if (slot == toSlot) return;
        _dragTo(slot);
      }
    }
  }

  void _dragTo(DraggableSlot to) {
    if (pickUp == null) return;
    final slots = relationship.keys.toList();
    final fromIndex = slots.indexOf(toSlot), toIndex = slots.indexOf(to);
    final start = math.min(fromIndex, toIndex),
        end = math.max(fromIndex, toIndex);
    // print('$start to $end');
    final key = relationship[to];
    final state = key?.currentState;
    // 目标是固定位置的，不进行移动操作
    if (state?.item?.fixed == true) {
      // print('移动失败');
      return;
    }
    // 前后互相移动
    if (end - start == 1) {
      // print('前后互相移动');
      if (key != pickUp) key?.currentState?.position = toSlot.position;
      relationship[toSlot] = key;
      relationship[to] = pickUp;
      toSlot = to;
    }
    // 多个移动
    else if (end - start > 1) {
      // print('跨多个slot');
      relationship[toSlot] = null;
      toSlot = to;
      if (fromIndex == start) {
        // 从前往后拖动
        print('从前往后拖动: 从 $start 到 $end');
        if (autoReorder || relationship[toSlot] != null) {
          reorder(start: start, end: end + 1);
          relationship[toSlot] = pickUp;
        }
      } else {
        // 将后面的item移动到前面
        print('将后面的item移动到前面: 从 $start 到 $end');
        DraggableSlot lastSlot = slots[start], currentSlot;
        GlobalKey<DraggableItemWidgetState> lastKey = relationship[lastSlot],
            currentKey;
        if (autoReorder || relationship[toSlot] != null) {
          relationship[toSlot] = null;
          for (var i = start + 1; i <= end; i++) {
            currentSlot = slots[i];
            currentKey = relationship[currentSlot];
            // print('i: $i ,${currentItem?.item.toString()}');
            if (currentKey?.currentState?.item?.fixed == true) continue;
            relationship[currentSlot] = lastKey;
            lastKey?.currentState?.position = currentSlot.position;
            lastKey = currentKey;
          }
        }
        setState(() {});
      }
      relationship[toSlot] = pickUp;
    }
  }

  @override
  onPanEnd(_) {
//    if (widget.allWayUseLongPress) gestures.remove(DraggableItemRecognizer);
    if (pickUp != null) {
      pickUp.currentState.position = toSlot.position;
      pickUp.currentState.active = false;
    }
    pickUp = toSlot = null;
    if (listEquals(_dragBeforeList, relationship.values.toList()) == false) {
      if (autoReorder) reorder();
      // print('changed');
      _triggerOnChanged();
    }
    _dragBeforeList.clear();

    setState(() {});
    if (widget.onDragEnd != null) widget.onDragEnd();
  }

  void _setGestures() {
    // 长按拖动 gestures[LongPressGestureRecognizer] = _longPressRecognizer;
    // 普通拖动 gestures[DraggableItemRecognizer] = _draggableItemRecognizer;

    if (_draggableMode) {
      // 在编辑模式
      if (widget.allWayUseLongPress) {
        gestures.remove(DraggableItemRecognizer);
      } else {
        gestures[DraggableItemRecognizer] = _draggableItemRecognizer;
      }
    } else {
      // 不在编辑模式
      gestures[LongPressGestureRecognizer] = _longPressRecognizer;
      gestures.remove(DraggableItemRecognizer);
    }
  }

  onLongPressStart(LongPressStartDetails details) {
    if (widget.readOnly)
      return;

    if (_draggableMode == false) {
      draggableMode = true;
      HapticFeedback.lightImpact();
    }

    if (_draggableMode ||
        (_draggableMode && widget.allWayUseLongPress == true)) {
      longPressPosition = details.localPosition;
      onPanStart(DragStartDetails(localPosition: details.localPosition));
    }

    setState(() {});
  }

  onLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    if (widget.readOnly)
      return;

    // print('onLongPressMoveUpdate');
    onPanUpdate(DragUpdateDetails(
        globalPosition: details.globalPosition,
        delta: details.localPosition - longPressPosition,
        localPosition: details.localPosition));
    longPressPosition = details.localPosition;
  }

  onLongPressEnd(_) {
    if (widget.readOnly)
      return;
    onPanEnd(null);
    draggableMode = false;
  }

  bool isDraggingItem(Offset globalPosition, Offset localPosition) {
    if (!_draggableMode) return false;
    final slot = findSlot(localPosition);
    final state = relationship[slot]?.currentState;
    if (slot == null || state == null) return false;
    if (state.item.fixed == true) return false;
    final HitTestResult result = HitTestResult();
    WidgetsBinding.instance.hitTest(result, globalPosition);
    for (HitTestEntry entry in result.path) {
      if (entry.target is RenderMetaData) {
        // print(entry.target);
        final RenderMetaData renderMetaData = entry.target;
        if (renderMetaData.metaData is ItemDeleteButton) {
          // print('点击了删除按钮');
          return false;
        }
      }
    }
    return true;
  }

  _updateChildren() {
    relationship.values
        .forEach((key) => key?.currentState?.draggableMode = _draggableMode);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      key: _containerKey,
      color: widget.color,
      constraints: BoxConstraints.expand(height: _maxHeight),
      child: RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        gestures: gestures,
        child: widget.willPopScope ? WillPopScope(
          onWillPop: () async {
            if (pickUp != null) return false;
            if (_draggableMode) {
              draggableMode = false;
              setState(() {});
              return false;
            }
            return true;
          },
          child: Stack(
            overflow: Overflow.visible,
            children: [...relationship.keys, ...layers],
          ),
        ) : Stack(
          overflow: Overflow.visible,
          children: [...relationship.keys, ...layers],
        ),
      ),
    );
  }
}

class DraggableSlot extends StatelessWidget {
  final double width, height;
  final BoxDecoration decoration;
  final Offset position;
  final DraggableContainerEventMixin event;
  final Offset maxPosition;

  const DraggableSlot(
      {Key key,
        this.width,
        this.height,
        this.decoration,
        this.position,
        this.maxPosition,
        this.event})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: position.dx,
      top: position.dy,
      width: width,
      height: height,
      child: Container(
        decoration: decoration,
      ),
    );
  }
}

class ItemDeleteButton extends StatelessWidget {
  final Widget child;
  final Function onTap;

  const ItemDeleteButton({Key key, this.onTap, this.child}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MetaData(
      metaData: this,
      child: GestureDetector(
        onTap: () {
          if (onTap != null) onTap();
        },
        child: child,
      ),
    );
  }
}

abstract class ItemWidgetEvent {
  updatePosition(Offset position);

  updateEditMode(bool editMode);

  updateActive(bool isActive);

  Offset get position;
}

mixin ItemWidgetEventMixin<T extends StatefulWidget> on State<T>
implements ItemWidgetEvent {}

class DraggableItemWidget<T extends DraggableItem> extends StatefulWidget {
  final T item;
  final double width, height;
  final BoxDecoration decoration;
  final DraggableItemsEvent stage;
  final Widget deleteButton;
  final Offset deleteButtonPosition;
  final Duration animateDuration;
  final bool editMode;
  final bool allowDrag;
  final Offset position;
  final Widget child;

  const DraggableItemWidget({
    Key key,
    this.item,
    this.width,
    this.height,
    this.decoration,
    this.position,
    this.stage,
    this.deleteButton,
    this.animateDuration,
    this.deleteButtonPosition,
    this.editMode: false,
    this.allowDrag: false,
    this.child,
  }) : super(key: key);

  @override
  DraggableItemWidgetState createState() => DraggableItemWidgetState<T>(item);
}

class DraggableItemWidgetState<T extends DraggableItem>
    extends State<DraggableItemWidget> {
  final T item;
  double x, y;
  bool _draggableMode = false;
  bool _active = false;
  Duration _duration;

  DraggableItemWidgetState(this.item);

  set draggableMode(bool value) {
    _draggableMode = value;
    setState(() {});
  }

  get draggableMode => _draggableMode;

  set active(bool value) {
    _active = value;
    _duration = _active ? Duration.zero : widget.animateDuration;
    setState(() {});
  }

  get active => _active;

  @override
  void initState() {
    super.initState();
    x = widget.position.dx;
    y = widget.position.dy;
    _draggableMode = widget.allowDrag;
    _duration = widget.animateDuration;
  }

  @override
  Widget build(BuildContext context) {
    // print('itemWidget build');
    final children = <Widget>[
      Padding(
        padding: EdgeInsets.only(top: widget.deleteButtonPosition.dy.abs()),
        child: Container(
          decoration: _active ? widget.decoration : null,
          width: widget.width + widget.deleteButtonPosition.dx,
          height: widget.height + widget.deleteButtonPosition.dy,
          child: IgnorePointer(
            ignoring: _draggableMode &&
                (widget.item.deletable && widget.item.fixed == false),
            ignoringSemantics: _draggableMode,
            child: item.child,
          ),
        ),
      )
    ];
    if (widget.editMode && widget.item.deletable) {
      if (widget.deleteButton == null) {
        throw Exception(
            'The deletable item need the delete button, but it is undefined');
      } else {
        children.add(Positioned(
          right: 0,
          top: 0,
          child: ItemDeleteButton(
            onTap: () {
              widget.stage._deleteFromKey(widget.key);
            },
            child: widget.deleteButton,
          ),
        ));
      }
    }
    return AnimatedPositioned(
      left: x,
      top: y,
      duration: _duration,
      width: widget.width,
      height: widget.height,
      child: Stack(children: children),
    );
  }

  _update() {
    if (mounted) setState(() {});
  }

  get position => Offset(x, y);

  set position(Offset position) {
    x = position.dx;
    y = position.dy;
    _update();
  }

  get maxPosition => Offset(widget.width + x, widget.height + y);
}

class DraggableItemRecognizer extends OneSequenceGestureRecognizer {
  Function onPanStart, onPanUpdate, onPanEnd;
  bool Function(Offset globalPosition, Offset localPosition) isHitItem;
  bool Function() isDraggingItem;
  final DraggableContainerState containerState;
  Offset widgetPosition = Offset.zero;

  DraggableItemRecognizer({@required this.containerState})
      : super(debugOwner: containerState);

  @override
  void addPointer(PointerDownEvent event) {
    startTrackingPointer(event.pointer);
    final RenderBox renderBox = containerState.context.findRenderObject();
    widgetPosition = renderBox.localToGlobal(Offset.zero);
    if (isHitItem(event.position, event.localPosition)) {
      // print('占用事件');
      resolve(GestureDisposition.accepted);
    } else
      resolve(GestureDisposition.rejected);
  }

  @override
  void handleEvent(PointerEvent event) {
    // print('handleEvent');
    final localPosition = event.position - widgetPosition;
    if (event is PointerDownEvent) {
      if (!isHitItem(event.position, localPosition)) return;
      onPanStart(DragStartDetails(
          globalPosition: event.position, localPosition: localPosition));
    } else if (event is PointerMoveEvent) {
      onPanUpdate(DragUpdateDetails(
          globalPosition: event.position,
          localPosition: localPosition,
          delta: event.delta));
    } else if (event is PointerUpEvent) {
      if (isDraggingItem()) onPanEnd(DragEndDetails());
      stopTrackingPointer(event.pointer);
    }
  }

  @override
  String get debugDescription => 'customPan';

  @override
  void didStopTrackingLastPointer(int pointer) {}
}