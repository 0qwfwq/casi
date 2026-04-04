// Imri — on-device AI assistant for the CASI launcher.
// Imri (pronounced "eem-ree") means 'my words spoken' / 'Eloquent'.
//
// Everything runs locally inside Flutter — no Python backend.
// LLM inference: llama_cpp_dart (llama.cpp via FFI)
// Persistent memory: sqflite (SQLite)

import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:llama_cpp_dart/llama_cpp_dart.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../morning_brief/weather_brief_service.dart';
import '../morning_brief/calendar_brief_service.dart';

// ---------------------------------------------------------------------------
// ImriMemory — SQLite-backed persistent memory
// ---------------------------------------------------------------------------

class ImriMemory {
  Database? _db;

  Future<void> initialize() async {
    try {
      final documentsDir = await getApplicationDocumentsDirectory();
      final dbPath = p.join(documentsDir.path, 'imri', 'aria_memory.db');
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
      debugPrint('[Imri] Memory database initialized.');
    } catch (e) {
      debugPrint('[Imri] Memory initialization error: $e');
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
        debugPrint('[Imri] Fact updated: $content');
      } else {
        await _db!.insert('explicit_facts', {
          'content': content,
          'importance': importance,
          'created_at': DateTime.now().toIso8601String(),
        });
        debugPrint('[Imri] Fact stored: $content');
      }
    } catch (e) {
      debugPrint('[Imri] storeFact error: $e');
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
      debugPrint('[Imri] getRelevantFacts error: $e');
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
      debugPrint('[Imri] recordAppLaunch error: $e');
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
      debugPrint('[Imri] getLikelyApps error: $e');
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
      debugPrint('[Imri] recordFeedback error: $e');
    }
  }
}

// ---------------------------------------------------------------------------
// GGUF architecture validation
// ---------------------------------------------------------------------------

/// Architectures supported by the llama.cpp bundled in llama_cpp_dart.
/// Models using unknown architectures are rejected before loading to
/// prevent native crashes.
const _supportedArchitectures = <String>{
  'llama', 'gpt2', 'gptj', 'gptneox', 'falcon', 'bloom', 'mpt',
  'starcoder', 'refact', 'bert', 'nomic-bert', 'jina-bert-v2',
  'stablelm', 'qwen', 'qwen2', 'qwen3', 'phi2', 'phi3', 'phi4',
  'plamo', 'codeshell', 'orion', 'internlm2', 'minicpm', 'minicpm3',
  'gemma', 'gemma2', 'gemma3', 'gemma4', 'starcoder2',
  'mamba', 'mamba2', 'xverse', 'command-r', 'dbrx', 'olmo', 'olmo2',
  'openelm', 'arctic', 'deepseek', 'deepseek2', 'deepseek3', 'chatglm',
  'bitnet', 't5', 't5encoder', 'jais', 'nemotron', 'exaone', 'rwkv6',
  'granite', 'chameleon', 'wavtokenizer',
};

/// Reads a GGUF file's `general.architecture` metadata value.
/// Returns `null` if the file isn't valid GGUF or the key isn't found.
Future<String?> _readGgufArchitecture(String path) async {
  // Run synchronously to avoid massive event loop hangs when skipping arrays
  RandomAccessFile? raf;
  try {
    raf = await File(path).open();

    // --- Header ---
    // 4B magic  |  4B version  |  8B tensor_count  |  8B kv_count
    final header = raf.readSync(24);
    if (header.length < 24) return null;
    final bd = ByteData.sublistView(header);

    final magic = String.fromCharCodes(header.sublist(0, 4));
    if (magic != 'GGUF') return null;

    final kvCount = bd.getUint64(16, Endian.little);

    // --- Iterate KV pairs looking for general.architecture ---
    for (int i = 0; i < kvCount; i++) {
      // Key: uint64 length + UTF-8 bytes
      final keyLenBytes = raf.readSync(8);
      if (keyLenBytes.length < 8) break;
      final keyLen = ByteData.sublistView(keyLenBytes).getUint64(0, Endian.little);
      final keyBytes = raf.readSync(keyLen);
      final key = String.fromCharCodes(keyBytes);

      // Value type: uint32
      final vtBytes = raf.readSync(4);
      if (vtBytes.length < 4) break;
      final vType = ByteData.sublistView(vtBytes).getUint32(0, Endian.little);

      if (key == 'general.architecture' && vType == 8 /* STRING */) {
        final sLenBytes = raf.readSync(8);
        final sLen = ByteData.sublistView(sLenBytes).getUint64(0, Endian.little);
        final sBytes = raf.readSync(sLen);
        return String.fromCharCodes(sBytes);
      }

      // Skip value we don't care about
      _skipGgufValueSync(raf, vType);
    }
    return null;
  } catch (e) {
    debugPrint('[Imri] _readGgufArchitecture error: $e');
    return null;
  } finally {
    raf?.closeSync();
  }
}

int _ggufValueSize(int vType) {
  switch (vType) {
    case 0: case 1: case 7: return 1;
    case 2: case 3: return 2;
    case 4: case 5: case 6: return 4;
    case 10: case 11: case 12: return 8;
    default: return -1;
  }
}

/// Skip over a GGUF metadata value in the file stream synchronously.
void _skipGgufValueSync(RandomAccessFile raf, int vType) {
  final fixedSize = _ggufValueSize(vType);
  if (fixedSize > 0) {
    raf.setPositionSync(raf.positionSync() + fixedSize);
    return;
  }

  switch (vType) {
    case 8: // STRING — uint64 len + bytes
      final lb = raf.readSync(8);
      final len = ByteData.sublistView(lb).getUint64(0, Endian.little);
      raf.setPositionSync(raf.positionSync() + len);
      break;
    case 9: // ARRAY — uint32 elemType + uint64 count + elements
      final ab = raf.readSync(12);
      final abd = ByteData.sublistView(ab);
      final elemType = abd.getUint32(0, Endian.little);
      final count = abd.getUint64(4, Endian.little);
      
      final elemSize = _ggufValueSize(elemType);
      if (elemSize > 0) {
        // Fast path for massive arrays of primitive types
        raf.setPositionSync(raf.positionSync() + (count * elemSize));
      } else {
        // Fallback for arrays of strings or nested arrays
        for (int j = 0; j < count; j++) {
          _skipGgufValueSync(raf, elemType);
        }
      }
      break;
    default:
      throw StateError('Unknown GGUF value type $vType');
  }
}

// ---------------------------------------------------------------------------
// ImriService — singleton, main interface
// ---------------------------------------------------------------------------

class ImriService {
  static final ImriService instance = ImriService._internal();

  factory ImriService() => instance;

  ImriService._internal();

  final ImriMemory _memory = ImriMemory();
  bool _modelLoaded = false;
  LlamaParent? _llamaParent;
  StreamSubscription<String>? _streamSub;
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
    final imriDir = Directory('${internalDir.path}/imri');
    if (!imriDir.existsSync()) imriDir.createSync(recursive: true);

    // Find any .gguf model in the imri directory
    final ggufFiles = imriDir.listSync().whereType<File>().where(
          (f) => f.path.endsWith('.gguf'),
        );

    if (ggufFiles.isNotEmpty) {
      final modelFile = ggufFiles.first.path;

      // Validate architecture before loading — prevents native crashes
      // from unsupported model architectures (e.g. qwen3 on old llama.cpp)
      final arch = await _readGgufArchitecture(modelFile);
      if (arch != null && !_supportedArchitectures.contains(arch)) {
        debugPrint('[Imri] Unsupported architecture "$arch" — removing model.');
        _modelError = 'Unsupported model architecture: "$arch". '
            'CASI supports: llama, qwen2/3, gemma2/3/4, phi3/4, and similar.';
        for (final f in imriDir.listSync()) {
          if (f is File && f.path.endsWith('.gguf')) {
            try { f.deleteSync(); } catch (_) {}
          }
        }
        return;
      }

      // Crash guard: if previous attempts to load/use this model caused crashes
      final prefs = await SharedPreferences.getInstance();
      final validated = prefs.getBool('imri_model_validated') ?? false;
      final attempts = prefs.getInt('imri_load_attempts') ?? 0;

      if (!validated && attempts >= 2) {
        debugPrint('[Imri] Model failed after $attempts attempts — removing bad model.');
        for (final f in imriDir.listSync()) {
          if (f is File && f.path.endsWith('.gguf')) {
            try { f.deleteSync(); } catch (_) {}
          }
        }
        await prefs.remove('imri_load_attempts');
        await prefs.remove('imri_model_validated');
        _modelError = 'Model crashed repeatedly and was removed. Try a different model.';
        debugPrint('[Imri] Bad model removed. Running in limited mode.');
        return;
      }

      // Increment attempt counter before loading (survives native crashes)
      await prefs.setInt('imri_load_attempts', attempts + 1);

      debugPrint('[Imri] Found model: ${modelFile.split('/').last} '
          '(arch: ${arch ?? 'unknown'}, attempt ${attempts + 1})');
      _modelPath = modelFile;
      await _loadModel(modelFile);

      if (_modelLoaded) {
        _validated = validated;
        if (validated) {
          // Model was already proven to work — reset counter
          await prefs.setInt('imri_load_attempts', 0);
        }
      }
    } else {
      debugPrint('[Imri] Model not found — running in limited mode.');
      debugPrint('[Imri] Call pickModelFile() to import the .gguf via file picker.');
    }
  }

  Future<void> _loadModel(String modelFile) async {
    try {
      final contextParams = ContextParams();
      contextParams.nCtx = 512;

      final samplingParams = SamplerParams();
      samplingParams.temp = 0.7;
      samplingParams.penaltyPresent = 0.3;

      final loadCommand = LlamaLoad(
        path: modelFile,
        modelParams: ModelParams(),
        contextParams: contextParams,
        samplingParams: samplingParams,
      );

      _llamaParent = LlamaParent(loadCommand);
      await _llamaParent!.init();
      _modelLoaded = true;
      debugPrint('[Imri] Ready.');
    } catch (e) {
      debugPrint('[Imri] _loadModel error: $e');
    }
  }

  /// Opens a file picker so the user can select the .gguf model file.
  /// Returns true if the model was successfully imported.
  Future<bool> pickModelFile({void Function(String)? onStatus}) async {
    debugPrint('[Imri] pickModelFile() called — opening file picker...');
    onStatus?.call('Opening file picker...');
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withReadStream: true,
      );
      debugPrint('[Imri] File picker returned: $result');

      if (result == null || result.files.single.path == null) {
        debugPrint('[Imri] File picker cancelled.');
        onStatus?.call('Cancelled');
        return false;
      }

      final platformFile = result.files.single;
      final pickedPath = platformFile.path!;
      
      if (!pickedPath.endsWith('.gguf')) {
        debugPrint('[Imri] Selected file is not a .gguf model.');
        _modelError = 'Selected file is not a .gguf model.';
        onStatus?.call('Invalid file type');
        return false;
      }

      onStatus?.call('Validating architecture...');
      // Validate architecture before copying (avoids wasting time + storage)
      final arch = await _readGgufArchitecture(pickedPath);
      if (arch != null && !_supportedArchitectures.contains(arch)) {
        debugPrint('[Imri] Rejected model: unsupported architecture "$arch"');
        _modelError = 'Unsupported model architecture: "$arch". '
            'CASI supports: llama, qwen2/3, gemma2/3/4, phi3/4, and similar.';
        onStatus?.call('Unsupported architecture');
        return false;
      }

      final internalDir = await getApplicationSupportDirectory();
      final imriDir = Directory('${internalDir.path}/imri');
      if (!imriDir.existsSync()) imriDir.createSync(recursive: true);

      onStatus?.call('Cleaning up old model...');
      // Remove any existing model files
      for (final f in imriDir.listSync()) {
        if (f is File && f.path.endsWith('.gguf')) {
          debugPrint('[Imri] Removing old model: ${f.path}');
          f.deleteSync();
        }
      }

      // Reset state before loading new model
      _modelLoaded = false;
      await _streamSub?.cancel();
      _streamSub = null;
      _llamaParent = null;
      _validated = false;
      _modelError = null;

      // Reset crash guard for new model
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('imri_model_validated', false);
      await prefs.setInt('imri_load_attempts', 0);

      final fileName = pickedPath.split('/').last;
      final destPath = '${imriDir.path}/$fileName';

      onStatus?.call('Copying model ($fileName)...');
      debugPrint('[Imri] Copying model: $fileName');
      
      // Use streams to avoid OOM or thread blocking on massive multi-GB model files
      final destFile = File(destPath);
      if (platformFile.readStream != null) {
        final sink = destFile.openWrite();
        await platformFile.readStream!.pipe(sink);
      } else {
        await File(pickedPath).copy(destPath);
      }
      
      debugPrint('[Imri] Model copied successfully.');

      onStatus?.call('Loading model...');
      _modelPath = destPath;
      await _loadModel(destPath);
      
      onStatus?.call('Done');
      return _modelLoaded;
    } catch (e, stack) {
      debugPrint('[Imri] pickModelFile error: $e');
      debugPrint('[Imri] Stack trace: $stack');
      onStatus?.call('Error importing model');
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
    debugPrint('[Imri] _runInferenceStreaming called. modelLoaded=$_modelLoaded');
    if (!_modelLoaded || _llamaParent == null) {
      debugPrint('[Imri] _runInferenceStreaming bailing: model not loaded.');
      return '';
    }
    try {
      // Qwen 3.5 models support /no_think to suppress <think> reasoning blocks.
      // Prepend it to the system prompt so the model outputs text directly.
      final prompt = '<|im_start|>system\n/no_think\n$systemPrompt<|im_end|>\n'
          '<|im_start|>user\n$userPrompt<|im_end|>\n'
          '<|im_start|>assistant\n';

      final buffer = StringBuffer();
      int lastWordEnd = 0;
      bool insideThink = false;
      final completer = Completer<String>();
      const stopTokens = [
        '<|im_end|>', '<|endoftext|>', '<eos>', '<|end|>', '</s>', '<think>',
      ];

      // Cancel any previous stream subscription before starting a new one
      await _streamSub?.cancel();
      _streamSub = _llamaParent!.stream.listen(
        (token) {
          if (completer.isCompleted) return;

          // Check for stop tokens
          for (final stop in stopTokens) {
            if (token.contains(stop)) {
              final output = buffer.toString()
                  .replaceAll(RegExp(r'<think>[\s\S]*?</think>'), '')
                  .trim();
              if (onToken != null && output.length > lastWordEnd) {
                onToken(output);
              }
              completer.complete(output);
              return;
            }
          }

          // Filter out <think>...</think> blocks
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
            if (text.length > lastWordEnd &&
                (text.endsWith(' ') || text.endsWith('\n'))) {
              lastWordEnd = text.length;
              onToken(trimmed);
            }
          }
        },
        onDone: () {
          if (!completer.isCompleted) {
            final output = buffer.toString()
                .replaceAll(RegExp(r'<think>[\s\S]*?</think>'), '')
                .trim();
            if (onToken != null && output.length > lastWordEnd) {
              onToken(output);
            }
            completer.complete(output);
          }
        },
        onError: (e) {
          debugPrint('[Imri] stream error: $e');
          if (!completer.isCompleted) {
            completer.complete(buffer.toString().trim());
          }
        },
      );

      _llamaParent!.sendPrompt(prompt);

      final output = await completer.future.timeout(
        const Duration(seconds: 60),
        onTimeout: () => buffer.toString().trim(),
      );

      // Mark model as validated after first successful inference
      if (!_validated && output.isNotEmpty) {
        _validated = true;
        SharedPreferences.getInstance().then((prefs) {
          prefs.setBool('imri_model_validated', true);
          prefs.setInt('imri_load_attempts', 0);
          debugPrint('[Imri] Model validated after successful inference.');
        });
      }

      return output;
    } catch (e) {
      debugPrint('[Imri] _runInferenceStreaming error: $e');
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
      debugPrint('[Imri] generateBriefMessage: model not loaded.');
      return null;
    }
    if (_generating) {
      debugPrint('[Imri] generateBriefMessage: already generating, skipping.');
      return null;
    }

    _generating = true;
    debugPrint('[Imri] generateBriefMessage: starting...');

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
          'You are Imri, an eloquent personal assistant woven into a phone launcher. '
          'Speak as though your words carry weight — concise yet expressive. '
          'Write a short, heartfelt greeting for one person. '
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
        maxTokens: 150,
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
      debugPrint('[Imri] generateBriefMessage result: "$raw"');

      _generating = false;

      if (raw.isEmpty) return null;

      var cleaned = raw.trim();
      if (cleaned.startsWith('"') && cleaned.endsWith('"')) {
        cleaned = cleaned.substring(1, cleaned.length - 1);
      }
      return cleaned.isEmpty ? null : cleaned;
    } catch (e) {
      debugPrint('[Imri] generateBriefMessage error: $e');
      _generating = false;
      return null;
    }
  }

  // ---------- Panel 2: Outfit & Weather Narratives ----------

  /// Generates a natural-language clothing recommendation from weather data.
  /// The decision model data is piped through Imri so the output feels like
  /// a thoughtful suggestion, not a logic-tree readout.
  Future<String?> generateOutfitNarrative({
    required WeatherBriefData weatherData,
    void Function(String partialText)? onWord,
  }) async {
    if (!_modelLoaded) return null;
    if (_generating) return null;

    _generating = true;
    debugPrint('[Imri] generateOutfitNarrative: starting...');

    try {
      final prefs = await SharedPreferences.getInstance();
      final unit = prefs.getString('temperature_unit') ?? 'C';
      final tempSpread = (weatherData.highTemp - weatherData.lowTemp).abs();

      final systemPrompt =
          'You are Imri, an eloquent clothing advisor. Recommend what WEIGHT and TYPE of clothing to wear based on the weather with well-chosen words. '
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
      debugPrint('[Imri] generateOutfitNarrative result: "$raw"');

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
      debugPrint('[Imri] generateOutfitNarrative error: $e');
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
    debugPrint('[Imri] generateWeatherNarrative: starting...');

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
          'You are Imri, an eloquent weather narrator. Write a natural, well-spoken summary of '
          "how the day's weather will unfold. Expressive yet concise — describe "
          'the arc and feel, not raw numbers. Just the summary, nothing else.';

      final userPrompt = 'Current: ${weatherData.overallCondition} at ${_tempStr(weatherData.currentTemp, unit)}.\n'
          'High: ${_tempStr(weatherData.highTemp, unit)}, Low: ${_tempStr(weatherData.lowTemp, unit)}.\n'
          '${periodDescriptions.isNotEmpty ? 'Periods: $periodDescriptions.\n' : ''}'
          'Write a natural weather narrative for today.';

      final raw = await _runInferenceStreaming(
        systemPrompt,
        userPrompt,
        maxTokens: 200,
        onToken: onWord != null
            ? (tokenBuffer) {
                var cleaned = tokenBuffer;
                if (cleaned.startsWith('"')) cleaned = cleaned.substring(1);
                onWord(cleaned);
              }
            : null,
      );
      debugPrint('[Imri] generateWeatherNarrative result: "$raw"');

      _generating = false;
      if (raw.isEmpty) return null;

      var cleaned = raw.trim();
      if (cleaned.startsWith('"') && cleaned.endsWith('"')) {
        cleaned = cleaned.substring(1, cleaned.length - 1);
      }
      return cleaned.isEmpty ? null : cleaned;
    } catch (e) {
      debugPrint('[Imri] generateWeatherNarrative error: $e');
      _generating = false;
      return null;
    }
  }

  // ---------- App tracking ----------

  Future<void> recordAppLaunch(String packageName) async {
    try {
      await _memory.recordAppLaunch(packageName);
    } catch (e) {
      debugPrint('[Imri] recordAppLaunch error: $e');
    }
  }

  // ---------- Memory ----------

  Future<void> rememberFact(String content, {int importance = 3}) async {
    try {
      await _memory.storeFact(content, importance: importance);
    } catch (e) {
      debugPrint('[Imri] rememberFact error: $e');
    }
  }

  // ---------- Pre-generation cache ----------

  static const _cacheKeyGreeting = 'imri_cached_greeting';
  static const _cacheKeyOutfit = 'imri_cached_outfit';
  static const _cacheKeyWeather = 'imri_cached_weather';
  static const _cacheKeyDate = 'imri_cached_date';

  /// Returns the date string for today (YYYY-MM-DD).
  static String _todayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  /// Save generated responses to SharedPreferences with today's date.
  Future<void> cacheResponses({
    String? greeting,
    String? outfit,
    String? weather,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final today = _todayKey();
    if (greeting != null) await prefs.setString(_cacheKeyGreeting, greeting);
    if (outfit != null) await prefs.setString(_cacheKeyOutfit, outfit);
    if (weather != null) await prefs.setString(_cacheKeyWeather, weather);
    await prefs.setString(_cacheKeyDate, today);
    debugPrint('[Imri] Cached responses for $today');
  }

  /// Load cached responses if they are from today.
  /// Returns null values if cache is stale (different day).
  Future<({String? greeting, String? outfit, String? weather})> loadCachedResponses() async {
    final prefs = await SharedPreferences.getInstance();
    final cachedDate = prefs.getString(_cacheKeyDate);
    final today = _todayKey();
    if (cachedDate != today) {
      debugPrint('[Imri] Cache is stale (cached: $cachedDate, today: $today)');
      return (greeting: null, outfit: null, weather: null);
    }
    return (
      greeting: prefs.getString(_cacheKeyGreeting),
      outfit: prefs.getString(_cacheKeyOutfit),
      weather: prefs.getString(_cacheKeyWeather),
    );
  }

  /// Pre-generate all brief responses and cache them.
  /// Called at midnight or when the day changes.
  Future<void> preGenerateForDay({
    WeatherBriefData? weatherData,
    CalendarBriefData? calendarData,
    Map<DateTime, List<dynamic>>? upcomingEvents,
  }) async {
    if (!_modelLoaded) return;
    debugPrint('[Imri] Pre-generating responses for ${_todayKey()}...');

    // Generate greeting
    final greeting = await generateBriefMessage(
      weatherData: weatherData,
      calendarData: calendarData,
      upcomingEvents: upcomingEvents,
    );

    String? outfit;
    String? weather;
    if (weatherData != null) {
      outfit = await generateOutfitNarrative(weatherData: weatherData);
      weather = await generateWeatherNarrative(weatherData: weatherData);
    }

    await cacheResponses(greeting: greeting, outfit: outfit, weather: weather);
    debugPrint('[Imri] Pre-generation complete.');
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
