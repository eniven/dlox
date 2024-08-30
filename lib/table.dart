class Table {
  final data = <String, Object>{};
  Table();

  Object? get(String key) {
    return data[key];
  }

  bool set(String key, Object value) {
    final hadKey = data.containsKey(key);
    data[key] = value;
    return !hadKey;
  }

  void delete(String key) {
    data.remove(key);
  }

  void addAll(Table other) {
    data.addAll(other.data);
  }
}
