// ARIA — on-device AI assistant for the CASI launcher.
//
// Everything runs locally inside Flutter — no Python backend.
// LLM inference: fllama (llama.cpp via FFI)
// Persistent memory: sqflite (SQLite)

import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:fllama/fllama.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../morning_brief/weather_brief_service.dart';
import '../morning_brief/calendar_brief_service.dart';

// ---------------------------------------------------------------------------
// ARIAMemory — SQLite-backed persistent memory
// ---------------------------------------------------------------------------

class ARIAMemory {
  Database? _db;

  Future<void> initialize() async {
    try {
      final documentsDir = await getApplicationDocumentsDirectory();
      final dbPath = p.join(documentsDir.path, 'aria', 'aria_memory.db');
      _db = await openDatabase(
        dbPath,
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS explicit_facts (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              content TEXT NOT NULL,
              importance INTEGER NOT NULL DEFAULT 3,
              created_at TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE IF NOT EXISTS app_launches (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              package_name TEXT NOT NULL,
              hour INTEGER NOT NULL,
              day_of_week INTEGER NOT NULL,
              timestamp TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE IF NOT EXISTS suggestion_log (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              suggestion_text TEXT NOT NULL,
              action TEXT NOT NULL,
              timestamp TEXT NOT NULL
            )
          ''');
        },
      );
      debugPrint('[ARIA] Memory database initialized.');
    } catch (e) {
      debugPrint('[ARIA] Memory initialization error: $e');
    }
  }

  Future<void> storeFact(String content, {int importance = 3}) async {
    try {
      if (_db == null) return;
      final existing = await _db!.query(
        'explicit_facts',
        where: 'content LIKE ?',
        whereArgs: ['%$content%'],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        await _db!.update(
          'explicit_facts',
          {
            'content': content,
            'importance': importance,
            'created_at': DateTime.now().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [existing.first['id']],
        );
        debugPrint('[ARIA] Fact updated: $content');
      } else {
        await _db!.insert('explicit_facts', {
          'content': content,
          'importance': importance,
          'created_at': DateTime.now().toIso8601String(),
        });
        debugPrint('[ARIA] Fact stored: $content');
      }
    } catch (e) {
      debugPrint('[ARIA] storeFact error: $e');
    }
  }

  Future<List<String>> getRelevantFacts(String query, {int limit = 3}) async {
    try {
      if (_db == null) return [];
      final words = query.toLowerCase().split(RegExp(r'\s+'));
      if (words.isEmpty) return [];

      final conditions =
          words.map((_) => 'LOWER(content) LIKE ?').join(' OR ');
      final args = words.map((w) => '%$w%').toList();

      final results = await _db!.query(
        'explicit_facts',
        where: conditions,
        whereArgs: args,
        orderBy: 'importance DESC, created_at DESC',
        limit: limit,
      );
      return results.map((r) => r['content'] as String).toList();
    } catch (e) {
      debugPrint('[ARIA] getRelevantFacts error: $e');
      return [];
    }
  }

  Future<void> recordAppLaunch(String packageName) async {
    try {
      if (_db == null) return;
      final now = DateTime.now();
      await _db!.insert('app_launches', {
        'package_name': packageName,
        'hour': now.hour,
        'day_of_week': now.weekday,
        'timestamp': now.toIso8601String(),
      });
    } catch (e) {
      debugPrint('[ARIA] recordAppLaunch error: $e');
    }
  }

  Future<List<String>> getLikelyApps({int limit = 4}) async {
    try {
      if (_db == null) return [];
      final sevenDaysAgo =
          DateTime.now().subtract(const Duration(days: 7)).toIso8601String();

      final results = await _db!.rawQuery('''
        SELECT package_name,
               SUM(CASE WHEN timestamp >= ? THEN 2 ELSE 1 END) AS score
        FROM app_launches
        GROUP BY package_name
        ORDER BY score DESC
        LIMIT ?
      ''', [sevenDaysAgo, limit]);

      return results.map((r) => r['package_name'] as String).toList();
    } catch (e) {
      debugPrint('[ARIA] getLikelyApps error: $e');
      return [];
    }
  }

  Future<void> recordFeedback(String suggestion, String action) async {
    try {
      if (_db == null) return;
      await _db!.insert('suggestion_log', {
        'suggestion_text': suggestion,
        'action': action,
        'timestamp': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('[ARIA] recordFeedback error: $e');
    }
  }
}

// ---------------------------------------------------------------------------
// GGUF architecture validation
// ---------------------------------------------------------------------------

/// Architectures supported by the llama.cpp bundled in fllama 0.0.1
/// (commit 54ef9cfc, Nov 2024). Models using newer architectures (e.g. qwen3)
/// will cause native crashes — we reject them before loading.
const _supportedArchitectures = <String>{
  'llama', 'gpt2', 'gptj', 'gptneox', 'falcon', 'bloom', 'mpt',
  'starcoder', 'refact', 'bert', 'nomic-bert', 'jina-bert-v2',
  'stablelm', 'qwen', 'qwen2', 'phi2', 'phi3', 'plamo', 'codeshell',
  'orion', 'internlm2', 'minicpm', 'gemma', 'gemma2', 'starcoder2',
  'mamba', 'xverse', 'command-r', 'dbrx', 'olmo', 'openelm', 'arctic',
  'deepseek', 'deepseek2', 'chatglm', 'bitnet', 't5', 't5encoder',
  'jais', 'nemotron', 'exaone', 'rwkv6',
};

/// Reads a GGUF file's `general.architecture` metadata value.
/// Returns `null` if the file isn't valid GGUF or the key isn't found.
Future<String?> _readGgufArchitecture(String path) async {
  RandomAccessFile? raf;
  try {
    raf = await File(path).open();

    // --- Header ---
    // 4B magic  |  4B version  |  8B tensor_count  |  8B kv_count
    final header = Uint8List(24);
    await raf.readInto(header);
    final bd = ByteData.sublistView(header);

    final magic = String.fromCharCodes(header.sublist(0, 4));
    if (magic != 'GGUF') return null;

    final kvCount = bd.getUint64(16, Endian.little);

    // --- Iterate KV pairs looking for general.architecture ---
    for (int i = 0; i < kvCount; i++) {
      // Key: uint64 length + UTF-8 bytes
      final keyLenBytes = Uint8List(8);
      await raf.readInto(keyLenBytes);
      final keyLen = ByteData.sublistView(keyLenBytes).getUint64(0, Endian.little);
      final keyBytes = Uint8List(keyLen);
      await raf.readInto(keyBytes);
      final key = String.fromCharCodes(keyBytes);

      // Value type: uint32
      final vtBytes = Uint8List(4);
      await raf.readInto(vtBytes);
      final vType = ByteData.sublistView(vtBytes).getUint32(0, Endian.little);

      if (key == 'general.architecture' && vType == 8 /* STRING */) {
        final sLenBytes = Uint8List(8);
        await raf.readInto(sLenBytes);
        final sLen = ByteData.sublistView(sLenBytes).getUint64(0, Endian.little);
        final sBytes = Uint8List(sLen);
        await raf.readInto(sBytes);
        return String.fromCharCodes(sBytes);
      }

      // Skip value we don't care about
      await _skipGgufValue(raf, vType);
    }
    return null;
  } catch (e) {
    debugPrint('[ARIA] _readGgufArchitecture error: $e');
    return null;
  } finally {
    raf?.close();
  }
}

/// Skip over a GGUF metadata value in the file stream.
Future<void> _skipGgufValue(RandomAccessFile raf, int vType) async {
  switch (vType) {
    case 0: // UINT8
    case 1: // INT8
    case 7: // BOOL
      await raf.setPosition(await raf.position() + 1);
    case 2: // UINT16
    case 3: // INT16
      await raf.setPosition(await raf.position() + 2);
    case 4: // UINT32
    case 5: // INT32
    case 6: // FLOAT32
      await raf.setPosition(await raf.position() + 4);
    case 10: // UINT64
    case 11: // INT64
    case 12: // FLOAT64
      await raf.setPosition(await raf.position() + 8);
    case 8: // STRING — uint64 len + bytes
      final lb = Uint8List(8);
      await raf.readInto(lb);
      final len = ByteData.sublistView(lb).getUint64(0, Endian.little);
      await raf.setPosition(await raf.position() + len);
    case 9: // ARRAY — uint32 elemType + uint64 count + elements
      final ab = Uint8List(12);
      await raf.readInto(ab);
      final abd = ByteData.sublistView(ab);
      final elemType = abd.getUint32(0, Endian.little);
      final count = abd.getUint64(4, Endian.little);
      for (int j = 0; j < count; j++) {
        await _skipGgufValue(raf, elemType);
      }
    default:
      // Unknown type — can't continue safely
      throw StateError('Unknown GGUF value type $vType');
  }
}

// ---------------------------------------------------------------------------
// ARIAService — singleton, main interface
// ---------------------------------------------------------------------------

class ARIAService {
  static final ARIAService instance = ARIAService._internal();

  factory ARIAService() => instance;

  ARIAService._internal();

  final ARIAMemory _memory = ARIAMemory();
  bool _modelLoaded = false;
  double? _contextId;
  String? _modelPath;
  String? _modelError; // non-null if model was rejected (e.g. unsupported arch)

  bool get isReady => _modelLoaded;
  String? get modelError => _modelError;

  bool _validated = false;

  // ---------- Lifecycle ----------

  Future<void> initialize() async {
    await _memory.initialize();

    // Use internal storage — always writable, no permissions needed
    final internalDir = await getApplicationSupportDirectory();
    final ariaDir = Directory('${internalDir.path}/aria');
    if (!ariaDir.existsSync()) ariaDir.createSync(recursive: true);

    // Find any .gguf model in the aria directory
    final ggufFiles = ariaDir.listSync().whereType<File>().where(
          (f) => f.path.endsWith('.gguf'),
        );

    if (ggufFiles.isNotEmpty) {
      final modelFile = ggufFiles.first.path;

      // Validate architecture before loading — prevents native crashes
      // from unsupported model architectures (e.g. qwen3 on old llama.cpp)
      final arch = await _readGgufArchitecture(modelFile);
      if (arch != null && !_supportedArchitectures.contains(arch)) {
        debugPrint('[ARIA] Unsupported architecture "$arch" — removing model.');
        _modelError = 'Unsupported model architecture: "$arch". '
            'This version of CASI supports: qwen2, llama, gemma2, phi3, and similar. '
            'Qwen 3.x models require a newer inference engine.';
        for (final f in ariaDir.listSync()) {
          if (f is File && f.path.endsWith('.gguf')) {
            try { f.deleteSync(); } catch (_) {}
          }
        }
        return;
      }

      // Crash guard: if previous attempts to load/use this model caused crashes
      final prefs = await SharedPreferences.getInstance();
      final validated = prefs.getBool('aria_model_validated') ?? false;
      final attempts = prefs.getInt('aria_load_attempts') ?? 0;

      if (!validated && attempts >= 2) {
        debugPrint('[ARIA] Model failed after $attempts attempts — removing bad model.');
        for (final f in ariaDir.listSync()) {
          if (f is File && f.path.endsWith('.gguf')) {
            try { f.deleteSync(); } catch (_) {}
          }
        }
        await prefs.remove('aria_load_attempts');
        await prefs.remove('aria_model_validated');
        _modelError = 'Model crashed repeatedly and was removed. Try a different model.';
        debugPrint('[ARIA] Bad model removed. Running in limited mode.');
        return;
      }

      // Increment attempt counter before loading (survives native crashes)
      await prefs.setInt('aria_load_attempts', attempts + 1);

      debugPrint('[ARIA] Found model: ${modelFile.split('/').last} '
          '(arch: ${arch ?? 'unknown'}, attempt ${attempts + 1})');
      _modelPath = modelFile;
      await _loadModel(modelFile);

      if (_modelLoaded) {
        _validated = validated;
        if (validated) {
          // Model was already proven to work — reset counter
          await prefs.setInt('aria_load_attempts', 0);
        }
      }
    } else {
      debugPrint('[ARIA] Model not found — running in limited mode.');
      debugPrint('[ARIA] Call pickModelFile() to import the .gguf via file picker.');
    }
  }

  Future<void> _loadModel(String modelFile) async {
    try {
      final fllama = Fllama.instance();
      if (fllama != null) {
        final result = await fllama.initContext(
          modelFile,
          nCtx: 512,
          nGpuLayers: 0,  // CPU-only — safest across all devices
        );
        if (result != null && result['contextId'] != null) {
          _contextId = double.parse(result['contextId'].toString());
          _modelLoaded = true;
          debugPrint('[ARIA] Ready. Context ID: $_contextId');
        } else {
          debugPrint('[ARIA] Failed to initialize model context.');
        }
      } else {
        debugPrint('[ARIA] Fllama instance not available.');
      }
    } catch (e) {
      debugPrint('[ARIA] _loadModel error: $e');
    }
  }

  /// Opens a file picker so the user can select the .gguf model file.
  /// Returns true if the model was successfully imported.
  Future<bool> pickModelFile() async {
    debugPrint('[ARIA] pickModelFile() called — opening file picker...');
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
      );
      debugPrint('[ARIA] File picker returned: $result');

      if (result == null || result.files.single.path == null) {
        debugPrint('[ARIA] File picker cancelled.');
        return false;
      }

      final pickedPath = result.files.single.path!;
      if (!pickedPath.endsWith('.gguf')) {
        debugPrint('[ARIA] Selected file is not a .gguf model.');
        _modelError = 'Selected file is not a .gguf model.';
        return false;
      }

      // Validate architecture before copying (avoids wasting time + storage)
      final arch = await _readGgufArchitecture(pickedPath);
      if (arch != null && !_supportedArchitectures.contains(arch)) {
        debugPrint('[ARIA] Rejected model: unsupported architecture "$arch"');
        _modelError = 'Unsupported model architecture: "$arch". '
            'This version of CASI supports: qwen2, llama, gemma2, phi3, and similar. '
            'Qwen 3.x models require a newer inference engine.';
        return false;
      }

      final internalDir = await getApplicationSupportDirectory();
      final ariaDir = Directory('${internalDir.path}/aria');
      if (!ariaDir.existsSync()) ariaDir.createSync(recursive: true);

      // Remove any existing model files
      for (final f in ariaDir.listSync()) {
        if (f is File && f.path.endsWith('.gguf')) {
          debugPrint('[ARIA] Removing old model: ${f.path}');
          f.deleteSync();
        }
      }

      // Reset state before loading new model
      _modelLoaded = false;
      _contextId = null;
      _validated = false;
      _modelError = null;

      // Reset crash guard for new model
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('aria_model_validated', false);
      await prefs.setInt('aria_load_attempts', 0);

      final fileName = pickedPath.split('/').last;
      final destPath = '${ariaDir.path}/$fileName';

      debugPrint('[ARIA] Copying model: $fileName');
      await File(pickedPath).copy(destPath);
      debugPrint('[ARIA] Model copied successfully.');

      _modelPath = destPath;
      await _loadModel(destPath);
      return _modelLoaded;
    } catch (e, stack) {
      debugPrint('[ARIA] pickModelFile error: $e');
      debugPrint('[ARIA] Stack trace: $stack');
      return false;
    }
  }

  // ---------- Inference ----------

  /// Streaming variant of inference — calls [onToken] with the accumulated
  /// text each time a new word boundary (whitespace) is detected, so the UI
  /// can reveal words one at a time.
  Future<String> _runInferenceStreaming(
    String systemPrompt,
    String userPrompt, {
    int maxTokens = 120,
    void Function(String accumulated)? onToken,
  }) async {
    debugPrint('[ARIA] _runInferenceStreaming called. modelLoaded=$_modelLoaded, contextId=$_contextId');
    if (!_modelLoaded || _contextId == null) {
      debugPrint('[ARIA] _runInferenceStreaming bailing: model not loaded or no context.');
      return '';
    }
    try {
      final fllama = Fllama.instance();
      if (fllama == null) {
        debugPrint('[ARIA] _runInferenceStreaming: Fllama instance is null.');
        return '';
      }

      // Qwen 3.5 models support /no_think to suppress <think> reasoning blocks.
      // Prepend it to the system prompt so the model outputs text directly.
      final prompt = '<|im_start|>system\n/no_think\n$systemPrompt<|im_end|>\n'
          '<|im_start|>user\n$userPrompt<|im_end|>\n'
          '<|im_start|>assistant\n';

      final buffer = StringBuffer();
      int lastWordEnd = 0;
      bool insideThink = false;

      late final StreamSubscription<Map<Object?, dynamic>> subscription;
      subscription = fllama.onTokenStream!.listen((data) {
        final function = data['function'] as String?;
        if (function == 'completion') {
          final result = data['result'];
          if (result is Map) {
            final token = result['token'] as String? ?? '';

            // Filter out <think>...</think> blocks in case the model still emits them
            if (token.contains('<think>')) { insideThink = true; return; }
            if (insideThink) {
              if (token.contains('</think>')) { insideThink = false; }
              return;
            }

            buffer.write(token);
            // Emit each time a new word boundary appears
            if (onToken != null) {
              final text = buffer.toString();
              final trimmed = text.trimRight();
              // Check if we've accumulated a new word (whitespace after content)
              if (text.length > lastWordEnd && (text.endsWith(' ') || text.endsWith('\n'))) {
                lastWordEnd = text.length;
                onToken(trimmed);
              }
            }
          }
        }
      });

      await fllama.completion(
        _contextId!,
        prompt: prompt,
        nPredict: maxTokens,
        temperature: 0.7,
        penaltyPresent: 0.3,
        emitRealtimeCompletion: true,
        stop: ['<|im_end|>', '<|endoftext|>', '<eos>', '<|end|>', '</s>', '<think>'],
      ).timeout(const Duration(seconds: 60));

      subscription.cancel();
      // Strip any residual <think>...</think> blocks from the output
      var output = buffer.toString().replaceAll(RegExp(r'<think>[\s\S]*?</think>'), '').trim();
      // Emit final text (last word may not have trailing space)
      if (onToken != null && output.length > lastWordEnd) {
        onToken(output);
      }

      // Mark model as validated after first successful inference
      if (!_validated) {
        _validated = true;
        SharedPreferences.getInstance().then((prefs) {
          prefs.setBool('aria_model_validated', true);
          prefs.setInt('aria_load_attempts', 0);
          debugPrint('[ARIA] Model validated after successful inference.');
        });
      }

      return output;
    } catch (e) {
      debugPrint('[ARIA] _runInferenceStreaming error: $e');
      return '';
    }
  }

  // ---------- Brief message generation ----------

  bool _generating = false;
  bool get isGenerating => _generating;

  /// Generates a context-aware greeting for Panel 1.
  /// Accepts weather, calendar, and upcoming event data so the greeting
  /// feels genuinely aware of the user's world.
  Future<String?> generateBriefMessage({
    void Function(String partialText)? onWord,
    WeatherBriefData? weatherData,
    CalendarBriefData? calendarData,
    Map<DateTime, List<dynamic>>? upcomingEvents,
  }) async {
    if (!_modelLoaded) {
      debugPrint('[ARIA] generateBriefMessage: model not loaded.');
      return null;
    }
    if (_generating) {
      debugPrint('[ARIA] generateBriefMessage: already generating, skipping.');
      return null;
    }

    _generating = true;
    debugPrint('[ARIA] generateBriefMessage: starting...');

    try {
      final now = DateTime.now();
      final timeOfDay = now.hour < 12
          ? 'morning'
          : now.hour < 17
              ? 'afternoon'
              : 'evening';
      final dayName = _dayName(now.weekday);
      final monthName = _monthName(now.month);
      final facts = await _memory.getRelevantFacts('today focus');
      final prefs = await SharedPreferences.getInstance();
      final userName = prefs.getString('user_name') ?? '';
      final unit = prefs.getString('temperature_unit') ?? 'C';

      // -- Build context sections --
      final contextParts = <String>[];

      // Weather context
      if (weatherData != null) {
        var weatherCtx = '${weatherData.overallCondition}, '
            '${_tempStr(weatherData.currentTemp, unit)} now, '
            'high ${_tempStr(weatherData.highTemp, unit)} low ${_tempStr(weatherData.lowTemp, unit)}.';
        if (weatherData.hasPrecipitation && weatherData.maxPrecipProbability >= 40) {
          weatherCtx += ' ${weatherData.maxPrecipProbability}% chance of precipitation.';
        }
        contextParts.add('Weather: $weatherCtx');
      }

      // Calendar context — today's device events
      if (calendarData != null && calendarData.events.isNotEmpty) {
        final eventSummaries = calendarData.events.take(4).map(_formatEventForPrompt).join('; ');
        contextParts.add("Today's events: $eventSummaries.");
      } else {
        contextParts.add('Schedule: clear today.');
      }

      // Upcoming launcher events (next 1-2 days)
      if (upcomingEvents != null && upcomingEvents.isNotEmpty) {
        final now = DateTime.now();
        final upcomingParts = <String>[];
        for (final entry in upcomingEvents.entries) {
          final date = entry.key;
          final events = entry.value;
          if (events.isEmpty) continue;
          final daysAway = date.difference(DateTime(now.year, now.month, now.day)).inDays;
          if (daysAway < 0 || daysAway > 2) continue;
          final label = daysAway == 0
              ? 'Today'
              : daysAway == 1
                  ? 'Tomorrow'
                  : _dayName(date.weekday);
          for (final e in events) {
            final title = e is String ? e : (e.title ?? '');
            if (title.isNotEmpty) upcomingParts.add('$label: $title');
          }
        }
        if (upcomingParts.isNotEmpty) {
          contextParts.add('Upcoming: ${upcomingParts.take(4).join('; ')}.');
        }
      }

      // Memory facts
      if (facts.isNotEmpty) {
        contextParts.add('About them: ${facts.join('; ')}.');
      }

      final systemPrompt =
          'You are ARIA, a warm personal assistant built into a phone launcher. '
          'Write a short, motivational greeting for one person. '
          'HARD RULES: '
          '1) Under 40 words. '
          '2) DO NOT state the date, day name, weather, or temperature — the user already sees those on screen. '
          '3) DO NOT invent events, facts, or plans the user does not have. Only reference events explicitly listed below. '
          '4) If the user has calendar events, reference ONE with brief encouragement (e.g. "Good luck on your quiz!" or "Enjoy your hangout tonight!"). '
          '5) If no events are listed, keep it simple and uplifting — do not fabricate activities. '
          '6) Just output the greeting text, nothing else — no quotes, no labels, no preamble.'
          '${userName.isNotEmpty ? ' The user\'s name is $userName. You may use it naturally.' : ''}';

      final userPrompt = 'RIGHT NOW: It is ${now.hour}:${now.minute.toString().padLeft(2, '0')} $timeOfDay on $dayName, $monthName ${now.day}, ${now.year}.\n'
          '${contextParts.join('\n')}\n'
          'Write a warm, personalized greeting. Do not mention the date, day, or weather directly. Do not invent anything not listed above.';

      final raw = await _runInferenceStreaming(
        systemPrompt,
        userPrompt,
        maxTokens: 80,
        onToken: onWord != null
            ? (tokenBuffer) {
                var cleaned = tokenBuffer;
                if (cleaned.startsWith('"')) {
                  cleaned = cleaned.substring(1);
                }
                onWord(cleaned);
              }
            : null,
      );
      debugPrint('[ARIA] generateBriefMessage result: "$raw"');

      _generating = false;

      if (raw.isEmpty) return null;

      var cleaned = raw.trim();
      if (cleaned.startsWith('"') && cleaned.endsWith('"')) {
        cleaned = cleaned.substring(1, cleaned.length - 1);
      }
      final words = cleaned.split(RegExp(r'\s+'));
      if (words.length > 50) {
        cleaned = words.take(50).join(' ');
      }
      return cleaned.isEmpty ? null : cleaned;
    } catch (e) {
      debugPrint('[ARIA] generateBriefMessage error: $e');
      _generating = false;
      return null;
    }
  }

  // ---------- Panel 2: Outfit & Weather Narratives ----------

  /// Generates a natural-language clothing recommendation from weather data.
  /// The decision model data is piped through ARIA so the output feels like
  /// a thoughtful suggestion, not a logic-tree readout.
  Future<String?> generateOutfitNarrative({
    required WeatherBriefData weatherData,
    void Function(String partialText)? onWord,
  }) async {
    if (!_modelLoaded) return null;
    if (_generating) return null;

    _generating = true;
    debugPrint('[ARIA] generateOutfitNarrative: starting...');

    try {
      final prefs = await SharedPreferences.getInstance();
      final unit = prefs.getString('temperature_unit') ?? 'C';
      final tempSpread = (weatherData.highTemp - weatherData.lowTemp).abs();

      final systemPrompt =
          'You are ARIA, a practical clothing advisor. Recommend what WEIGHT and TYPE of clothing to wear based on the weather. '
          'HARD RULES: '
          '1) Under 25 words. One or two short sentences. '
          '2) Focus ONLY on clothing weight and type: light/heavy, layers, shorts vs pants, jacket vs no jacket. '
          '3) DO NOT suggest colors, patterns, styles, or brands. '
          '4) If hot: suggest shorts, t-shirt, sunscreen or hat. '
          '5) If cold: suggest heavy coat, layers, warm pants. '
          '6) If mild: suggest light jacket or sweater, pants. '
          '7) If rain: mention umbrella or rain jacket. '
          '8) Just output the recommendation, nothing else — no quotes, no labels.';

      final userPrompt = 'Weather right now: ${weatherData.overallCondition}, ${_tempStr(weatherData.currentTemp, unit)}. '
          'High ${_tempStr(weatherData.highTemp, unit)}, low ${_tempStr(weatherData.lowTemp, unit)}. '
          'Temperature spread: ${_tempStr(tempSpread, unit)}. '
          '${weatherData.hasPrecipitation ? 'Rain chance: ${weatherData.maxPrecipProbability}%.' : 'No rain expected.'} '
          'What weight and type of clothing should I wear?';

      final raw = await _runInferenceStreaming(
        systemPrompt,
        userPrompt,
        maxTokens: 50,
        onToken: onWord != null
            ? (tokenBuffer) {
                var cleaned = tokenBuffer;
                if (cleaned.startsWith('"')) cleaned = cleaned.substring(1);
                onWord(cleaned);
              }
            : null,
      );
      debugPrint('[ARIA] generateOutfitNarrative result: "$raw"');

      _generating = false;
      if (raw.isEmpty) return null;

      var cleaned = raw.trim();
      if (cleaned.startsWith('"') && cleaned.endsWith('"')) {
        cleaned = cleaned.substring(1, cleaned.length - 1);
      }
      final words = cleaned.split(RegExp(r'\s+'));
      if (words.length > 25) cleaned = words.take(25).join(' ');
      return cleaned.isEmpty ? null : cleaned;
    } catch (e) {
      debugPrint('[ARIA] generateOutfitNarrative error: $e');
      _generating = false;
      return null;
    }
  }

  /// Generates a natural-language weather narrative from forecast data.
  /// Communicates the arc of the day: what it feels like now, what's coming,
  /// and roughly when — something you'd actually want to read.
  Future<String?> generateWeatherNarrative({
    required WeatherBriefData weatherData,
    void Function(String partialText)? onWord,
  }) async {
    if (!_modelLoaded) return null;
    if (_generating) return null;

    _generating = true;
    debugPrint('[ARIA] generateWeatherNarrative: starting...');

    try {
      final prefs = await SharedPreferences.getInstance();
      final unit = prefs.getString('temperature_unit') ?? 'C';

      // Build period descriptions for the prompt
      final periodDescriptions = weatherData.periods.take(3).map((p) {
        final timeLabel = p.startHour == DateTime.now().hour
            ? 'Now'
            : _hourLabel(p.startHour);
        return '$timeLabel: ${p.condition}, ${_tempStr(p.avgTemp, unit)}'
            '${p.maxPrecipProb > 30 ? ', ${p.maxPrecipProb}% precip' : ''}';
      }).join('. ');

      final systemPrompt =
          'You are ARIA, a personal weather narrator. Write a natural summary of '
          "how the day's weather will unfold. Under 70 words. Conversational — describe "
          'the arc and feel, not raw numbers. Just the summary, nothing else.';

      final userPrompt = 'Current: ${weatherData.overallCondition} at ${_tempStr(weatherData.currentTemp, unit)}.\n'
          'High: ${_tempStr(weatherData.highTemp, unit)}, Low: ${_tempStr(weatherData.lowTemp, unit)}.\n'
          '${periodDescriptions.isNotEmpty ? 'Periods: $periodDescriptions.\n' : ''}'
          'Write a natural weather narrative for today.';

      final raw = await _runInferenceStreaming(
        systemPrompt,
        userPrompt,
        maxTokens: 120,
        onToken: onWord != null
            ? (tokenBuffer) {
                var cleaned = tokenBuffer;
                if (cleaned.startsWith('"')) cleaned = cleaned.substring(1);
                onWord(cleaned);
              }
            : null,
      );
      debugPrint('[ARIA] generateWeatherNarrative result: "$raw"');

      _generating = false;
      if (raw.isEmpty) return null;

      var cleaned = raw.trim();
      if (cleaned.startsWith('"') && cleaned.endsWith('"')) {
        cleaned = cleaned.substring(1, cleaned.length - 1);
      }
      final words = cleaned.split(RegExp(r'\s+'));
      if (words.length > 80) cleaned = words.take(80).join(' ');
      return cleaned.isEmpty ? null : cleaned;
    } catch (e) {
      debugPrint('[ARIA] generateWeatherNarrative error: $e');
      _generating = false;
      return null;
    }
  }

  // ---------- App tracking ----------

  Future<void> recordAppLaunch(String packageName) async {
    try {
      await _memory.recordAppLaunch(packageName);
    } catch (e) {
      debugPrint('[ARIA] recordAppLaunch error: $e');
    }
  }

  // ---------- Memory ----------

  Future<void> rememberFact(String content, {int importance = 3}) async {
    try {
      await _memory.storeFact(content, importance: importance);
    } catch (e) {
      debugPrint('[ARIA] rememberFact error: $e');
    }
  }

  // ---------- Helpers ----------

  String _tempStr(double celsius, String unit) {
    final val = unit == 'F' ? (celsius * 9 / 5 + 32).round() : celsius.round();
    return '$val°$unit';
  }

  String _dayName(int weekday) {
    const days = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday',
      'Friday', 'Saturday', 'Sunday',
    ];
    return days[weekday - 1];
  }

  String _monthName(int month) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return months[month - 1];
  }

  String _hourLabel(int hour) {
    if (hour == 0) return '12 AM';
    if (hour < 12) return '$hour AM';
    if (hour == 12) return '12 PM';
    return '${hour - 12} PM';
  }

  String _formatEventForPrompt(DeviceCalendarEvent event) {
    final time = event.allDay ? 'all day' : event.timeString;
    return '${event.title} ($time)';
  }
}
