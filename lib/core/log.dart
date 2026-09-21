import 'dart:collection';
import 'dart:developer' as dev;

class AppLog {
  AppLog._(this.tag);
  factory AppLog.tag(String tag) => AppLog._(tag);

  final String tag;
  static const int _ringCapacity = 500;
  static final Queue<LogEntry> _ring = Queue<LogEntry>();
  static LogLevel minLevel = LogLevel.verbose;
  static List<LogEntry> snapshot() => List.unmodifiable(_ring);
  static void clear() => _ring.clear();

  void v(String msg, {Object? error, StackTrace? stack}) => _emit(LogLevel.verbose, msg, error, stack);
  void d(String msg, {Object? error, StackTrace? stack}) => _emit(LogLevel.debug, msg, error, stack);
  void i(String msg, {Object? error, StackTrace? stack}) => _emit(LogLevel.info, msg, error, stack);
  void w(String msg, {Object? error, StackTrace? stack}) => _emit(LogLevel.warn, msg, error, stack);
  void e(String msg, {Object? error, StackTrace? stack}) => _emit(LogLevel.error, msg, error, stack);

  void _emit(LogLevel lvl, String msg, Object? err, StackTrace? st) {
    if (lvl.index < minLevel.index) return;
    final entry = LogEntry(ts: DateTime.now(), level: lvl, tag: tag, message: msg, error: err?.toString(), stack: st?.toString());
    _ring.addLast(entry);
    while (_ring.length > _ringCapacity) {
      _ring.removeFirst();
    }
    dev.log(msg, time: entry.ts, name: tag, level: lvl.devLevel, error: err, stackTrace: st);
  }
}

enum LogLevel {
  verbose(500), debug(700), info(800), warn(900), error(1000);
  const LogLevel(this.devLevel);
  final int devLevel;
}

class LogEntry {
  LogEntry({required this.ts, required this.level, required this.tag, required this.message, this.error, this.stack});
  final DateTime ts;
  final LogLevel level;
  final String tag;
  final String message;
  final String? error;
  final String? stack;
  String get formatted {
    final t = ts.toIso8601String().substring(11, 23);
    final lvl = level.name.substring(0, 1).toUpperCase();
    final body = error == null ? message : '$message  err=$error';
    return '$t $lvl/$tag  $body';
  }
}
