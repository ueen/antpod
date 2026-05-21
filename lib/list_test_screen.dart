import 'dart:async';

import 'package:flutter/material.dart';

// Test screen replicating _EpisodeFeed's exact stream-switch + _diffUpdate logic.
// Long-press the AntPod logo to reach this screen.

class ListTestScreen extends StatefulWidget {
  const ListTestScreen({super.key});
  @override
  State<ListTestScreen> createState() => _ListTestScreenState();
}

class _ListTestScreenState extends State<ListTestScreen> {
  final _listKey = GlobalKey<SliverAnimatedListState>();
  final _displayed = <int>[];
  List<int> _raw = [];
  bool _initialLoad = true;
  bool _filterNewOnly = false; // false = all, true = "new only" (subset)
  Timer? _debounce;
  StreamSubscription<List<int>>? _sub;

  // Mock data: "all" has 20 items, "new only" has 14 (first 14)
  static final _allItems  = List.generate(20, (i) => i);
  static final _newItems  = List.generate(14, (i) => i);

  List<int> get _currentDataset => _filterNewOnly ? _newItems : _allItems;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  // Same as home screen: switch stream on filter change, keep _initialLoad=false
  void _toggleFilter() {
    _filterNewOnly = !_filterNewOnly;
    _debounce?.cancel();
    _sub?.cancel();
    _subscribe(); // does NOT reset _initialLoad
  }

  // Same as home screen: switch stream on filter change, but RESET _initialLoad
  void _toggleFilterWithReset() {
    _filterNewOnly = !_filterNewOnly;
    _debounce?.cancel();
    _sub?.cancel();
    setState(() {
      _initialLoad = true;
      _displayed.clear();
    });
    _subscribe();
  }

  void _subscribe() {
    // sync: true mirrors Drift — first event fires synchronously inside listen(),
    // so _onData runs during initState and _displayed is populated before first build.
    final ctrl = StreamController<List<int>>(sync: true);
    _sub = ctrl.stream.listen(_onData);
    ctrl.add(List.from(_currentDataset)); // fires synchronously → _initialLoad path
    // Simulate a second emit 30ms later (e.g. a position-update DB write)
    Future.delayed(const Duration(milliseconds: 30), () {
      if (!ctrl.isClosed) ctrl.add(List.from(_currentDataset));
    });
    Future.delayed(const Duration(milliseconds: 200), ctrl.close);
  }

  void _onData(List<int> next) {
    _raw = next;
    if (_initialLoad) {
      setState(() {
        _displayed.clear();
        _displayed.addAll(next);
        _initialLoad = false;
      });
      return;
    }
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 80), () {
      _diffUpdate(List.from(_raw));
    });
  }

  void _diffUpdate(List<int> next) {
    final state = _listKey.currentState;
    if (state == null) {
      setState(() { _displayed..clear()..addAll(next); });
      return;
    }

    final nextSet = next.toSet();
    final displayedSet = _displayed.toSet();

    int removed = 0, added = 0;
    for (int i = _displayed.length - 1; i >= 0; i--) {
      if (!nextSet.contains(_displayed[i])) {
        final item = _displayed.removeAt(i);
        state.removeItem(i, (ctx, anim) => _exitTile(item, anim),
            duration: const Duration(milliseconds: 300));
        removed++;
      }
    }
    for (int i = 0; i < next.length; i++) {
      if (!displayedSet.contains(next[i])) {
        _displayed.insert(i, next[i]);
        state.insertItem(i, duration: const Duration(milliseconds: 300));
        added++;
      }
    }

    if (removed + added == 0) {
      setState(() {}); // same as home screen's "pure data update" path
    }
  }

  // Single manual remove (simulates marking episode as read)
  void _removeSingle(int idx) {
    if (idx < 0 || idx >= _displayed.length) return;
    final item = _displayed.removeAt(idx);
    _listKey.currentState?.removeItem(idx, (ctx, anim) => _exitTile(item, anim),
        duration: const Duration(milliseconds: 300));
  }

  Widget _buildTile(int id, Color color, Animation<double> anim) {
    return SizeTransition(
      sizeFactor: CurvedAnimation(parent: anim, curve: Curves.easeOut),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        height: 64,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Text('Item #$id', style: const TextStyle(fontSize: 16)),
      ),
    );
  }

  Widget _exitTile(int id, Animation<double> anim) {
    return SizeTransition(
      sizeFactor: CurvedAnimation(parent: anim, curve: Curves.easeIn),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        height: 64,
        decoration: BoxDecoration(color: Colors.red.shade100, borderRadius: BorderRadius.circular(8)),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Text('Item #$id', style: const TextStyle(fontSize: 16)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('List Test  [${_filterNewOnly ? "new only (14)" : "all (20)"}]  displayed=${_displayed.length}'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Wrap(
              spacing: 8, runSpacing: 8,
              children: [
                ElevatedButton(
                  onPressed: () => _removeSingle(2),
                  child: const Text('Remove idx 2'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                  onPressed: () => setState(() {}),
                  child: const Text('setState'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue, foregroundColor: Colors.white),
                  onPressed: _toggleFilter,
                  child: Text(_filterNewOnly ? '→ show all' : '→ new only'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green, foregroundColor: Colors.white),
                  onPressed: _toggleFilterWithReset,
                  child: Text(_filterNewOnly ? '→ all (reset)' : '→ new (reset)'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: CustomScrollView(
              slivers: [
                SliverAnimatedList(
                  key: _listKey,
                  initialItemCount: _displayed.length,
                  itemBuilder: (ctx, i, anim) => _buildTile(_displayed[i], Colors.blue.shade50, anim),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
