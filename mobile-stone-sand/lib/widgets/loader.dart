import 'package:flutter/widgets.dart';

import '../data/db.dart';

/// One async query: keeps the last data while reloading and drops stale responses.
class Loader<T> extends ChangeNotifier {
  Loader(this._fetch);

  Future<T> Function() _fetch;
  T? data;
  String? error;
  bool loading = false;
  int _seq = 0;
  bool _disposed = false;

  bool get pending => loading && data == null;

  void setFetch(Future<T> Function() fetch) => _fetch = fetch;

  Future<void> load() async {
    final seq = ++_seq;
    loading = true;
    error = null;
    _notify();
    try {
      final result = await _fetch();
      if (seq != _seq) return;
      data = result;
    } catch (e) {
      if (seq != _seq) return;
      error = errorText(e);
    } finally {
      if (seq == _seq) {
        loading = false;
        _notify();
      }
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Reloads [loaders] whenever any write bumps [dataVersion].
mixin ReloadOnDataChange<W extends StatefulWidget> on State<W> {
  List<Loader<dynamic>> get loaders;

  @override
  void initState() {
    super.initState();
    dataVersion.addListener(_onData);
  }

  void _onData() {
    if (!mounted) return;
    for (final l in loaders) {
      l.load();
    }
  }

  Future<void> reloadAll() => Future.wait(loaders.map((l) => l.load()));

  @override
  void dispose() {
    dataVersion.removeListener(_onData);
    super.dispose();
  }
}
