// Foresight — App categorizer.
//
// Classical Information Retrieval pipeline that maps unknown apps to
// [AppCapability] tags without an LLM. For every newly-installed package
// the rule engine doesn't already know about, this service:
//
//   1. Fetches the app's Play Store listing over plain HTTPS.
//   2. Parses the Play Store category (deterministic, well-defined) and
//      the developer-supplied description.
//   3. Maps the category to capability tags via a hand-curated table.
//   4. Runs a lightweight keyword classifier over the description for
//      finer-grained tags Play Store categories don't capture (e.g.
//      "note_taking" inside a generic PRODUCTIVITY app).
//   5. Calls [AppCapabilityMap.registerOverride] so the rule engine
//      picks the app up on the next predict() tick.
//
// Modded / sideloaded apps (ReVanced, Vanced, *Morphe builds) and
// region-locked apps aren't on the Play Store at all. For those we run
// a *name-based* classifier over the package name + app display name
// against a single-word vocabulary, then fall through to a generic
// `utility` tag so every app gets *something* — nothing stays invisible
// just because it isn't on Google's CDN.
//
// Results are persisted to SharedPreferences so we don't re-fetch on
// every launcher startup. Session-only attempt tracking means a mod
// that has no internet listing today can still be re-classified next
// session if its name was edited or new keywords were added.
//
// This deliberately avoids word-embedding bundles: a curated keyword
// table is small, fast, deterministic, and good enough for surfacing
// the right *capability class*. The Play Store category does the heavy
// lifting; keywords only refine the granular intent.

import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'foresight_capabilities.dart';

/// One entry in the categorizer's work queue. Carries the package name
/// (used for both Play Store lookup and substring classification) plus
/// the on-device display name (which often gives away mods — "YT Music
/// Morphe", "Lawnchair", "Newpipe").
class _QueuedApp {
  final String packageName;
  final String? appName;
  const _QueuedApp(this.packageName, this.appName);
}

class AppCategorizer {
  AppCategorizer._();
  static final AppCategorizer instance = AppCategorizer._();

  static const String _prefsKey = 'foresight_categorizer_overrides_v1';
  static const Duration _requestTimeout = Duration(seconds: 8);
  static const Duration _interRequestDelay = Duration(milliseconds: 250);

  /// Last-resort tag set for apps where we have no signal at all —
  /// Play Store rejects the package and no name keyword matches. The
  /// `utility` tag lets them surface for low-battery / catch-up needs
  /// instead of being permanently invisible to the rule engine.
  static const List<String> _fallbackTags = [AppCapability.utility];

  final Queue<_QueuedApp> _queue = Queue<_QueuedApp>();

  /// Packages we've already attempted *this session*. Cleared on every
  /// launcher restart so mods that were edited or skipped earlier get
  /// another chance.
  final Set<String> _attempted = <String>{};

  bool _running = false;
  bool _hydrated = false;

  /// Load previously-cached overrides from disk so apps that were
  /// already classified in a prior session light up instantly. Safe to
  /// call multiple times — only runs once.
  Future<void> hydrate() async {
    if (_hydrated) return;
    _hydrated = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) return;
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      decoded.forEach((pkg, tags) {
        if (tags is List) {
          AppCapabilityMap.registerOverride(
              pkg, tags.cast<String>().toList(growable: false));
        }
      });
      debugPrint('[Categorizer] hydrated ${decoded.length} cached override(s)');
    } catch (e) {
      debugPrint('[Categorizer] hydrate error: $e');
    }
  }

  /// Queue every (package, name) pair the rule engine doesn't already
  /// know about. Idempotent within a session — packages already tried
  /// in this run are skipped. Packages already classified by either the
  /// hardcoded patterns OR a hydrated override are skipped because
  /// `AppCapabilityMap.isKnown` returns true for them.
  void enqueue(Iterable<({String packageName, String? appName})> apps) {
    var added = 0;
    for (final entry in apps) {
      final pkg = entry.packageName;
      if (_attempted.contains(pkg)) continue;
      if (AppCapabilityMap.isKnown(pkg)) continue;
      _queue.add(_QueuedApp(pkg, entry.appName));
      added++;
    }
    if (added > 0) {
      debugPrint('[Categorizer] queued $added unknown app(s)');
      _drain();
    }
  }

  // -------------------------------------------------------------------------
  // Worker loop
  // -------------------------------------------------------------------------

  Future<void> _drain() async {
    if (_running) return;
    _running = true;
    try {
      while (_queue.isNotEmpty) {
        final job = _queue.removeFirst();
        if (_attempted.contains(job.packageName)) continue;
        _attempted.add(job.packageName);

        final tags = await _categorizeAlways(job);
        AppCapabilityMap.registerOverride(job.packageName, tags);
        await _persistOverride(job.packageName, tags);
        debugPrint('[Categorizer] ${job.packageName} → $tags');

        await Future.delayed(_interRequestDelay);
      }
    } finally {
      _running = false;
    }
  }

  // -------------------------------------------------------------------------
  // Persistence
  // -------------------------------------------------------------------------

  Future<void> _persistOverride(String pkg, List<String> tags) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    Map<String, dynamic> decoded;
    if (raw == null) {
      decoded = <String, dynamic>{};
    } else {
      try {
        decoded = jsonDecode(raw) as Map<String, dynamic>;
      } catch (_) {
        decoded = <String, dynamic>{};
      }
    }
    decoded[pkg] = tags;
    await prefs.setString(_prefsKey, jsonEncode(decoded));
  }

  // -------------------------------------------------------------------------
  // Categorization — three layers, merged.
  //
  //   1. Play Store fetch (best signal — explicit category, real description).
  //   2. Local name classifier (works for sideloads, mods, AOSP-only apps).
  //   3. Fallback `[utility]` so every queued app gets a non-empty tag set.
  //
  // We always run all three layers and union the results. A mod app that
  // 404s on the Play Store still gets tagged from its name; an obscure
  // app whose name says nothing still gets `utility` so the launcher
  // can surface it for at least *some* need.
  // -------------------------------------------------------------------------

  Future<List<String>> _categorizeAlways(_QueuedApp job) async {
    final tags = <String>{};

    // Layer 1: Play Store. Best-effort — failures are normal for mods.
    try {
      final psTags = await _fetchPlayStoreTags(job.packageName);
      tags.addAll(psTags);
    } catch (e) {
      debugPrint(
          '[Categorizer] play-store ${job.packageName} failed: $e');
    }

    // Layer 2: name classifier over package + display name. This is
    // what catches "YT Music Morphe", "ReVanced YouTube", "Newpipe",
    // "Samsung Music", and anything else with a self-describing name.
    tags.addAll(_classifyByName(job.appName, job.packageName));

    // Layer 3: ensure we never store an empty tag set. The rule engine
    // ignores any app with no tags, so an empty set means the app is
    // effectively invisible — that's worse than a generic guess.
    if (tags.isEmpty) {
      tags.addAll(_fallbackTags);
    }
    return tags.toList(growable: false);
  }

  Future<Set<String>> _fetchPlayStoreTags(String packageName) async {
    final url = Uri.parse('https://play.google.com/store/apps/details')
        .replace(queryParameters: {'id': packageName, 'hl': 'en'});

    final response = await http.get(url, headers: {
      'User-Agent':
          'Mozilla/5.0 (Linux; Android 14; CASI Launcher) '
          'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Mobile',
    }).timeout(_requestTimeout);

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }

    final body = response.body;
    final genreId = _extractGenreId(body);
    final description = _extractDescription(body) ?? '';

    final tags = <String>{};
    tags.addAll(_genreIdToTags(genreId));
    tags.addAll(_classifyByKeywords('$description $genreId'));
    return tags;
  }

  // ---- HTML extraction ----

  /// Pull the Play Store category id (e.g. `MUSIC_AND_AUDIO`) from a
  /// `/store/apps/category/<ID>` link in the listing. This id is stable
  /// and well-documented, unlike the localized display name.
  static final RegExp _genreIdRegex =
      RegExp(r'/store/apps/category/([A-Z_]+)');

  /// Fallback: the human-readable genre that lives in the page header.
  static final RegExp _genreNameRegex =
      RegExp(r'itemprop="genre"[^>]*>([^<]+)<', caseSensitive: false);

  /// The `<meta name="description">` tag carries a clean short summary.
  static final RegExp _descRegex = RegExp(
    r'<meta[^>]+name="description"[^>]+content="([^"]+)"',
    caseSensitive: false,
  );

  static String _extractGenreId(String html) {
    final m = _genreIdRegex.firstMatch(html);
    if (m != null) return m.group(1)!;
    final n = _genreNameRegex.firstMatch(html);
    return n?.group(1)?.toUpperCase().replaceAll(' ', '_') ?? '';
  }

  static String? _extractDescription(String html) {
    final m = _descRegex.firstMatch(html);
    if (m == null) return null;
    return _decodeHtmlEntities(m.group(1) ?? '');
  }

  static String _decodeHtmlEntities(String s) => s
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&nbsp;', ' ');

  // ---- Deterministic Play Store category → capability tags ----
  //
  // Source: Google's published Play Store category ids. Anything inside
  // GAME_* maps to the same gaming bucket; the rest is exhaustive
  // enough that 80%+ of installed apps get categorized purely from the
  // category line, no description parsing required.

  static const Map<String, List<String>> _genreIdTags = {
    'COMMUNICATION': [
      AppCapability.communication,
      AppCapability.messaging,
    ],
    'SOCIAL': [AppCapability.social],
    'DATING': [AppCapability.social],
    'MAPS_AND_NAVIGATION': [
      AppCapability.navigation,
      AppCapability.location,
      AppCapability.commute,
      AppCapability.traffic,
    ],
    'AUTO_AND_VEHICLES': [
      AppCapability.navigation,
      AppCapability.commute,
      AppCapability.utility,
    ],
    'TRAVEL_AND_LOCAL': [
      AppCapability.travel,
      AppCapability.navigation,
      AppCapability.location,
    ],
    'WEATHER': [AppCapability.weather],
    'MUSIC_AND_AUDIO': [
      AppCapability.music,
      AppCapability.audio,
      AppCapability.entertainment,
    ],
    'VIDEO_PLAYERS': [
      AppCapability.video,
      AppCapability.entertainment,
      AppCapability.streaming,
    ],
    'ENTERTAINMENT': [AppCapability.entertainment],
    'NEWS_AND_MAGAZINES': [
      AppCapability.news,
      AppCapability.reading,
      AppCapability.articles,
    ],
    'BOOKS_AND_REFERENCE': [
      AppCapability.books,
      AppCapability.reading,
    ],
    'COMICS': [
      AppCapability.entertainment,
      AppCapability.reading,
    ],
    'EDUCATION': [AppCapability.education],
    'BUSINESS': [
      AppCapability.professional,
      AppCapability.productivity,
    ],
    'PRODUCTIVITY': [AppCapability.productivity],
    'TOOLS': [AppCapability.utility],
    'PERSONALIZATION': [
      AppCapability.utility,
      AppCapability.settings,
    ],
    'LIBRARIES_AND_DEMO': [AppCapability.utility],
    'FINANCE': [
      AppCapability.finance,
      AppCapability.banking,
    ],
    'HEALTH_AND_FITNESS': [
      AppCapability.health,
      AppCapability.fitness,
    ],
    'MEDICAL': [AppCapability.health],
    'LIFESTYLE': [AppCapability.discovery],
    'FOOD_AND_DRINK': [
      AppCapability.food,
      AppCapability.restaurants,
    ],
    'SHOPPING': [AppCapability.shopping],
    'PHOTOGRAPHY': [
      AppCapability.camera,
      AppCapability.photography,
      AppCapability.gallery,
      AppCapability.photos,
    ],
    'ART_AND_DESIGN': [
      AppCapability.inspiration,
      AppCapability.discovery,
    ],
    'HOUSE_AND_HOME': [
      AppCapability.utility,
      AppCapability.shopping,
    ],
    'PARENTING': [AppCapability.utility],
    'EVENTS': [
      AppCapability.scheduling,
      AppCapability.calendar,
    ],
    'BEAUTY': [
      AppCapability.discovery,
      AppCapability.shopping,
    ],
    'SPORTS': [
      AppCapability.entertainment,
      AppCapability.news,
    ],
  };

  static List<String> _genreIdToTags(String id) {
    if (id.isEmpty) return const [];
    if (id.startsWith('GAME')) {
      return const [
        AppCapability.gaming,
        AppCapability.entertainment,
      ];
    }
    return _genreIdTags[id] ?? const [];
  }

  // ---- Description keyword classifier (multi-word) ----
  //
  // Substring matching against a curated phrase vocabulary. Designed
  // for free-form developer descriptions — phrases are specific enough
  // ("video call", "task manager") to avoid the false positives that
  // single words ("video", "task") would trigger inside marketing copy.

  static const Map<String, List<String>> _keywordTags = {
    // Notes / docs / tasks
    'note-taking': [AppCapability.noteTaking],
    'note taking': [AppCapability.noteTaking],
    'notebook': [AppCapability.noteTaking],
    'notes app': [AppCapability.noteTaking],
    'reminder': [AppCapability.reminders],
    'todo list': [AppCapability.tasks, AppCapability.reminders],
    'to-do list': [AppCapability.tasks, AppCapability.reminders],
    'task manager': [AppCapability.tasks, AppCapability.productivity],
    'project management': [
      AppCapability.projectManagement,
      AppCapability.productivity,
    ],
    'kanban': [
      AppCapability.projectManagement,
      AppCapability.productivity,
    ],
    'document editor': [
      AppCapability.documentEditing,
      AppCapability.productivity,
    ],
    'spreadsheet': [
      AppCapability.documentEditing,
      AppCapability.productivity,
    ],
    'presentation': [
      AppCapability.documentEditing,
      AppCapability.productivity,
    ],
    'pdf': [AppCapability.documentEditing, AppCapability.reading],

    // Comms / scheduling
    'email client': [AppCapability.email, AppCapability.communication],
    ' inbox': [AppCapability.email],
    'mail app': [AppCapability.email],
    'video call': [AppCapability.videoCall, AppCapability.meeting],
    'video meeting': [
      AppCapability.videoCall,
      AppCapability.meeting,
      AppCapability.conference,
    ],
    'team chat': [
      AppCapability.communication,
      AppCapability.messaging,
      AppCapability.professional,
    ],
    'calendar': [AppCapability.calendar, AppCapability.scheduling],
    'scheduling': [AppCapability.scheduling],

    // Audio / video
    'music streaming': [
      AppCapability.music,
      AppCapability.audio,
      AppCapability.streaming,
    ],
    'podcast': [AppCapability.podcasts, AppCapability.audio],
    'audiobook': [AppCapability.audiobooks, AppCapability.audio],
    'video streaming': [
      AppCapability.video,
      AppCapability.streaming,
      AppCapability.entertainment,
    ],
    'live tv': [AppCapability.video, AppCapability.streaming],

    // Health / fitness
    'workout': [AppCapability.fitness, AppCapability.health],
    'fitness tracker': [AppCapability.fitness, AppCapability.health],
    'running': [
      AppCapability.running,
      AppCapability.fitness,
      AppCapability.health,
    ],
    'cycling': [AppCapability.fitness, AppCapability.health],
    'meditation': [
      AppCapability.meditation,
      AppCapability.windDown,
      AppCapability.health,
    ],
    'sleep tracking': [
      AppCapability.sleepTools,
      AppCapability.windDown,
      AppCapability.health,
    ],
    'nutrition': [AppCapability.nutrition, AppCapability.health],
    'calorie': [AppCapability.nutrition, AppCapability.health],

    // Money
    'banking': [AppCapability.banking, AppCapability.finance],
    'mobile bank': [AppCapability.banking, AppCapability.finance],
    'investing': [AppCapability.finance],
    'cryptocurrency': [AppCapability.finance],
    'payment': [AppCapability.payments],
    'wallet': [AppCapability.payments],

    // Food / shopping / travel
    'food delivery': [AppCapability.delivery, AppCapability.food],
    'restaurant': [AppCapability.restaurants, AppCapability.food],
    'recipe': [AppCapability.food],
    'flight': [AppCapability.flights, AppCapability.travel],
    'hotel': [AppCapability.travel],
    'travel planner': [AppCapability.travel],
    'shopping': [AppCapability.shopping],

    // Security
    'authenticator': [
      AppCapability.authentication,
      AppCapability.security,
    ],
    'two-factor': [
      AppCapability.authentication,
      AppCapability.security,
    ],
    '2fa': [AppCapability.authentication, AppCapability.security],
    'password manager': [
      AppCapability.passwords,
      AppCapability.security,
    ],
    'vpn': [AppCapability.security, AppCapability.utility],

    // Camera / photos / reading
    'camera app': [AppCapability.camera, AppCapability.photography],
    'photo editor': [AppCapability.photography, AppCapability.gallery],
    'gallery': [AppCapability.gallery, AppCapability.photos],
    'ebook': [AppCapability.books, AppCapability.reading],
    'news app': [AppCapability.news, AppCapability.reading],

    // Education / campus
    'campus': [
      AppCapability.education,
      AppCapability.campusPortal,
    ],
    'university': [
      AppCapability.education,
      AppCapability.campusPortal,
    ],
    'lecture': [
      AppCapability.lectureCompanion,
      AppCapability.education,
    ],
    'flashcard': [
      AppCapability.education,
      AppCapability.lectureCompanion,
    ],
    'language learning': [AppCapability.education],
  };

  static Set<String> _classifyByKeywords(String text) {
    if (text.isEmpty) return <String>{};
    final lower = text.toLowerCase();
    final tags = <String>{};
    for (final entry in _keywordTags.entries) {
      if (lower.contains(entry.key)) tags.addAll(entry.value);
    }
    return tags;
  }

  // ---- Name classifier (single-word, for package + display names) ----
  //
  // Runs over the package name + on-device display name only. Names are
  // short and self-descriptive ("YT Music Morphe", "Samsung Notes",
  // "com.sec.android.app.music"), so single-word substring matching is
  // safer here than in free-form descriptions. This is the layer that
  // catches sideloaded mods which never appear on the Play Store.

  static const Map<String, List<String>> _nameKeywords = {
    // Audio / video
    'music': [
      AppCapability.music,
      AppCapability.audio,
      AppCapability.entertainment,
    ],
    'audio': [AppCapability.audio],
    'spotify': [
      AppCapability.music,
      AppCapability.audio,
      AppCapability.entertainment,
    ],
    'podcast': [AppCapability.podcasts, AppCapability.audio],
    'audiobook': [
      AppCapability.audiobooks,
      AppCapability.audio,
      AppCapability.reading,
    ],
    'youtube': [AppCapability.video, AppCapability.entertainment],
    'netflix': [
      AppCapability.video,
      AppCapability.entertainment,
      AppCapability.streaming,
    ],
    'video': [AppCapability.video, AppCapability.entertainment],
    'movie': [AppCapability.video, AppCapability.entertainment],
    'tv': [AppCapability.video, AppCapability.entertainment],
    'radio': [AppCapability.audio, AppCapability.entertainment],
    'player': [AppCapability.audio, AppCapability.video],

    // Comms
    'mail': [AppCapability.email, AppCapability.communication],
    'gmail': [AppCapability.email, AppCapability.communication],
    'inbox': [AppCapability.email, AppCapability.communication],
    'messenger': [AppCapability.messaging, AppCapability.communication],
    'message': [AppCapability.messaging, AppCapability.communication],
    'sms': [
      AppCapability.sms,
      AppCapability.messaging,
      AppCapability.communication,
    ],
    'chat': [AppCapability.messaging, AppCapability.communication],
    'phone': [AppCapability.phone, AppCapability.communication],
    'dialer': [AppCapability.phone, AppCapability.communication],
    'contacts': [AppCapability.phone, AppCapability.communication],
    'whatsapp': [AppCapability.messaging, AppCapability.communication],
    'signal': [AppCapability.messaging, AppCapability.communication],
    'telegram': [AppCapability.messaging, AppCapability.communication],
    'discord': [
      AppCapability.communication,
      AppCapability.messaging,
      AppCapability.gamingSocial,
    ],
    'slack': [
      AppCapability.communication,
      AppCapability.messaging,
      AppCapability.professional,
    ],
    'meet': [
      AppCapability.videoCall,
      AppCapability.meeting,
      AppCapability.conference,
    ],
    'zoom': [
      AppCapability.videoCall,
      AppCapability.meeting,
      AppCapability.conference,
    ],
    'teams': [
      AppCapability.videoCall,
      AppCapability.meeting,
      AppCapability.conference,
    ],

    // Productivity / docs / notes
    'notes': [AppCapability.noteTaking, AppCapability.productivity],
    'note': [AppCapability.noteTaking, AppCapability.productivity],
    'keep': [AppCapability.noteTaking, AppCapability.productivity],
    'docs': [
      AppCapability.documentEditing,
      AppCapability.productivity,
    ],
    'doc': [
      AppCapability.documentEditing,
      AppCapability.productivity,
    ],
    'sheets': [
      AppCapability.documentEditing,
      AppCapability.productivity,
    ],
    'slides': [
      AppCapability.documentEditing,
      AppCapability.productivity,
    ],
    'word': [
      AppCapability.documentEditing,
      AppCapability.productivity,
    ],
    'excel': [
      AppCapability.documentEditing,
      AppCapability.productivity,
    ],
    'powerpoint': [
      AppCapability.documentEditing,
      AppCapability.productivity,
    ],
    'office': [AppCapability.productivity, AppCapability.documentEditing],
    'task': [AppCapability.tasks, AppCapability.productivity],
    'todo': [AppCapability.tasks, AppCapability.productivity],
    'reminder': [AppCapability.reminders, AppCapability.productivity],
    'planner': [AppCapability.productivity, AppCapability.scheduling],

    // Time / scheduling
    'calendar': [AppCapability.calendar, AppCapability.scheduling],
    'clock': [
      AppCapability.clock,
      AppCapability.alarm,
      AppCapability.timer,
    ],
    'alarm': [AppCapability.alarm, AppCapability.clock],
    'timer': [AppCapability.timer, AppCapability.clock],

    // Navigation
    'maps': [
      AppCapability.navigation,
      AppCapability.location,
    ],
    'navigation': [AppCapability.navigation, AppCapability.location],
    'waze': [
      AppCapability.navigation,
      AppCapability.location,
      AppCapability.commute,
      AppCapability.traffic,
    ],
    'uber': [
      AppCapability.rideshare,
      AppCapability.commute,
    ],
    'lyft': [
      AppCapability.rideshare,
      AppCapability.commute,
    ],
    'transit': [AppCapability.transit, AppCapability.commute],

    // Camera / photos
    'camera': [AppCapability.camera, AppCapability.photography],
    'photo': [AppCapability.photography, AppCapability.gallery],
    'gallery': [AppCapability.gallery, AppCapability.photos],

    // Browser / web
    'browser': [AppCapability.browser, AppCapability.web],
    'chrome': [AppCapability.browser, AppCapability.web],
    'firefox': [AppCapability.browser, AppCapability.web],
    'edge': [AppCapability.browser, AppCapability.web],
    'opera': [AppCapability.browser, AppCapability.web],
    'brave': [AppCapability.browser, AppCapability.web],
    'duckduckgo': [
      AppCapability.browser,
      AppCapability.web,
      AppCapability.search,
    ],

    // Reading / news
    'news': [AppCapability.news, AppCapability.reading, AppCapability.articles],
    'reader': [AppCapability.reading, AppCapability.articles],
    'kindle': [AppCapability.books, AppCapability.reading],
    'book': [AppCapability.books, AppCapability.reading],
    'feedly': [AppCapability.reading, AppCapability.news],
    'pocket': [AppCapability.reading, AppCapability.articles],

    // Social
    'instagram': [AppCapability.social, AppCapability.photoSharing],
    'facebook': [AppCapability.social],
    'twitter': [AppCapability.social, AppCapability.news],
    'reddit': [
      AppCapability.social,
      AppCapability.reading,
      AppCapability.news,
    ],
    'tiktok': [
      AppCapability.social,
      AppCapability.entertainment,
      AppCapability.video,
    ],
    'snapchat': [AppCapability.social, AppCapability.messaging],
    'pinterest': [
      AppCapability.social,
      AppCapability.inspiration,
      AppCapability.discovery,
    ],
    'linkedin': [AppCapability.social, AppCapability.professional],
    'threads': [AppCapability.social],
    'mastodon': [AppCapability.social],
    'bluesky': [AppCapability.social],

    // Health / fitness
    'fitness': [AppCapability.fitness, AppCapability.health],
    'workout': [AppCapability.fitness, AppCapability.health],
    'gym': [AppCapability.fitness, AppCapability.health],
    'strava': [
      AppCapability.fitness,
      AppCapability.health,
      AppCapability.running,
    ],
    'health': [AppCapability.health],
    'meditation': [
      AppCapability.meditation,
      AppCapability.windDown,
      AppCapability.health,
    ],
    'sleep': [
      AppCapability.sleepTools,
      AppCapability.windDown,
      AppCapability.health,
    ],

    // Money
    'wallet': [AppCapability.payments],
    'pay': [AppCapability.payments],
    'venmo': [AppCapability.banking, AppCapability.finance],
    'paypal': [AppCapability.banking, AppCapability.finance],
    'cashapp': [AppCapability.banking, AppCapability.finance],
    'bank': [AppCapability.banking, AppCapability.finance],
    'finance': [AppCapability.finance],

    // Food / shopping / travel
    'food': [AppCapability.food],
    'recipe': [AppCapability.food],
    'doordash': [AppCapability.food, AppCapability.delivery],
    'ubereats': [AppCapability.food, AppCapability.delivery],
    'shop': [AppCapability.shopping],
    'store': [AppCapability.shopping],
    'amazon': [AppCapability.shopping],
    'flight': [AppCapability.flights, AppCapability.travel],
    'travel': [AppCapability.travel],
    'weather': [AppCapability.weather],

    // Security / utilities
    'authenticator': [
      AppCapability.authentication,
      AppCapability.security,
    ],
    'authy': [
      AppCapability.authentication,
      AppCapability.security,
    ],
    'password': [AppCapability.passwords, AppCapability.security],
    'bitwarden': [AppCapability.passwords, AppCapability.security],
    '1password': [AppCapability.passwords, AppCapability.security],
    'vpn': [AppCapability.security, AppCapability.utility],
    'calculator': [AppCapability.calculator, AppCapability.utility],
    'settings': [AppCapability.settings, AppCapability.system],

    // Games / mods
    'game': [AppCapability.gaming, AppCapability.entertainment],
    'minecraft': [AppCapability.gaming, AppCapability.entertainment],
  };

  static Set<String> _classifyByName(String? appName, String packageName) {
    final tags = <String>{};
    final hay = '${(appName ?? '').toLowerCase()} '
        '${packageName.toLowerCase()}';
    if (hay.trim().isEmpty) return tags;
    for (final entry in _nameKeywords.entries) {
      if (hay.contains(entry.key)) tags.addAll(entry.value);
    }
    return tags;
  }
}
