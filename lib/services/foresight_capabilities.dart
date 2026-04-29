// Foresight — App capability knowledge base.
//
// Static map from package-name substring → list of capability tags that
// describe what the app *does*. The Foresight rule engine matches inferred
// user "needs" against these tags to decide which apps to surface.
//
// This is intentionally a hand-curated knowledge base — every entry is
// a deliberate claim about what an app is for. Add new apps freely;
// matching is substring-based on the lowercased package name.
//
// To extend: add to the map below, or call [registerOverride] at runtime
// for user-installed apps the launcher discovers.

class AppCapability {
  /// Communication / messaging
  static const communication = 'communication';
  static const messaging = 'messaging';
  static const sms = 'sms';
  static const phone = 'phone';
  static const videoCall = 'video_call';
  static const email = 'email';

  /// Productivity / education
  static const noteTaking = 'note_taking';
  static const lectureCompanion = 'lecture_companion';
  static const campusPortal = 'campus_portal';
  static const education = 'education';
  static const documentEditing = 'document_editing';
  static const productivity = 'productivity';
  static const tasks = 'tasks';
  static const reminders = 'reminders';
  static const projectManagement = 'project_management';
  static const professional = 'professional';
  static const meeting = 'meeting';
  static const conference = 'conference';

  /// Time / scheduling
  static const calendar = 'calendar';
  static const scheduling = 'scheduling';
  static const clock = 'clock';
  static const alarm = 'alarm';
  static const timer = 'timer';

  /// Navigation / commute
  static const navigation = 'navigation';
  static const location = 'location';
  static const commute = 'commute';
  static const transit = 'transit';
  static const rideshare = 'rideshare';
  static const traffic = 'traffic';

  /// Audio / podcasts / music
  static const music = 'music';
  static const audio = 'audio';
  static const podcasts = 'podcasts';
  static const audiobooks = 'audiobooks';

  /// Video / entertainment
  static const video = 'video';
  static const entertainment = 'entertainment';
  static const streaming = 'streaming';
  static const gaming = 'games';
  static const gamingSocial = 'gaming_social';

  /// Reading / news
  static const reading = 'reading';
  static const books = 'books';
  static const articles = 'articles';
  static const news = 'news';

  /// Social / discovery
  static const social = 'social';
  static const photoSharing = 'photo_sharing';
  static const inspiration = 'inspiration';
  static const discovery = 'discovery';

  /// Web / browser / search
  static const browser = 'browser';
  static const web = 'web';
  static const search = 'search';

  /// Camera / gallery
  static const camera = 'camera';
  static const photography = 'photography';
  static const gallery = 'gallery';
  static const photos = 'photos';

  /// Health / fitness
  static const fitness = 'fitness';
  static const health = 'health';
  static const running = 'running';
  static const nutrition = 'nutrition';
  static const meditation = 'meditation';
  static const sleepTools = 'sleep_tools';
  static const windDown = 'wind_down';

  /// Money
  static const banking = 'banking';
  static const finance = 'finance';
  static const payments = 'payments';

  /// Food
  static const food = 'food';
  static const delivery = 'delivery';
  static const restaurants = 'restaurants';

  /// Shopping
  static const shopping = 'shopping';

  /// Security / utilities
  static const authentication = 'authentication';
  static const passwords = 'passwords';
  static const security = 'security';
  static const calculator = 'calculator';
  static const utility = 'utility';
  static const system = 'system';
  static const settings = 'settings';

  /// Travel / weather
  static const travel = 'travel';
  static const weather = 'weather';
  static const flights = 'flights';
}

class AppCapabilityMap {
  AppCapabilityMap._();

  /// User overrides applied at runtime (e.g. settings UI lets the user
  /// re-tag an app). These are checked before the built-in patterns.
  static final Map<String, List<String>> _userOverrides = {};

  /// Substring patterns matched against the lowercased package name.
  /// Order is irrelevant — every pattern that matches contributes its tags.
  /// Keep this list in alphabetical-ish groups by category for readability.
  static const Map<String, List<String>> _patterns = {
    // ---------- Communication ----------
    'com.google.android.apps.messaging': [
      AppCapability.communication, AppCapability.messaging, AppCapability.sms,
    ],
    'com.samsung.android.messaging': [
      AppCapability.communication, AppCapability.messaging, AppCapability.sms,
    ],
    'com.android.mms': [
      AppCapability.communication, AppCapability.messaging, AppCapability.sms,
    ],
    'com.android.messaging': [
      AppCapability.communication, AppCapability.messaging, AppCapability.sms,
    ],
    'com.google.android.dialer': [
      AppCapability.communication, AppCapability.phone,
    ],
    'com.samsung.android.dialer': [
      AppCapability.communication, AppCapability.phone,
    ],
    'com.android.phone': [
      AppCapability.communication, AppCapability.phone,
    ],
    'com.android.contacts': [
      AppCapability.communication, AppCapability.phone,
    ],
    'whatsapp': [
      AppCapability.communication, AppCapability.messaging,
      AppCapability.videoCall,
    ],
    'org.thoughtcrime.securesms': [ // Signal
      AppCapability.communication, AppCapability.messaging,
    ],
    'org.telegram': [
      AppCapability.communication, AppCapability.messaging,
    ],
    'com.beeper': [
      AppCapability.communication, AppCapability.messaging,
    ],
    'im.vector.app': [ // Element / Matrix
      AppCapability.communication, AppCapability.messaging,
    ],
    'discord': [
      AppCapability.communication, AppCapability.messaging,
      AppCapability.gamingSocial,
    ],
    'slack': [
      AppCapability.communication, AppCapability.messaging,
      AppCapability.professional,
    ],
    'com.microsoft.teams': [
      AppCapability.communication, AppCapability.messaging,
      AppCapability.meeting, AppCapability.videoCall, AppCapability.conference,
      AppCapability.professional,
    ],
    'us.zoom.videomeetings': [
      AppCapability.meeting, AppCapability.videoCall, AppCapability.conference,
    ],
    'com.cisco.webex': [
      AppCapability.meeting, AppCapability.videoCall, AppCapability.conference,
    ],
    'com.google.android.apps.meetings': [
      AppCapability.meeting, AppCapability.videoCall, AppCapability.conference,
    ],
    'com.google.android.apps.tachyon': [ // Google Meet / Duo
      AppCapability.videoCall, AppCapability.meeting,
    ],

    // ---------- Email ----------
    'gmail': [
      AppCapability.email, AppCapability.communication,
      AppCapability.professional,
    ],
    'outlook': [
      AppCapability.email, AppCapability.communication,
      AppCapability.professional, AppCapability.calendar,
    ],
    'protonmail': [
      AppCapability.email, AppCapability.communication,
    ],
    'thunderbird': [
      AppCapability.email, AppCapability.communication,
    ],
    'com.samsung.android.email': [
      AppCapability.email, AppCapability.communication,
    ],

    // ---------- Calendar / scheduling ----------
    'com.google.android.calendar': [
      AppCapability.calendar, AppCapability.scheduling,
    ],
    'com.samsung.android.calendar': [
      AppCapability.calendar, AppCapability.scheduling,
    ],
    'com.microsoft.office.outlook': [ // some builds use this id
      AppCapability.email, AppCapability.calendar,
      AppCapability.professional,
    ],

    // ---------- Education / campus ----------
    'instructure.canvas': [ // Canvas Student
      AppCapability.education, AppCapability.campusPortal,
      AppCapability.lectureCompanion,
    ],
    'instructure.candroid': [
      AppCapability.education, AppCapability.campusPortal,
      AppCapability.lectureCompanion,
    ],
    'com.blackboard': [
      AppCapability.education, AppCapability.campusPortal,
    ],
    'blackboard': [
      AppCapability.education, AppCapability.campusPortal,
    ],
    'com.moodle': [
      AppCapability.education, AppCapability.campusPortal,
    ],
    'edu': [ // weak match — many campus apps include 'edu'
      AppCapability.education, AppCapability.campusPortal,
    ],
    'duolingo': [
      AppCapability.education, AppCapability.entertainment,
    ],
    'khanacademy': [
      AppCapability.education,
    ],
    'quizlet': [
      AppCapability.education, AppCapability.lectureCompanion,
    ],

    // ---------- Note-taking / docs ----------
    'com.google.android.keep': [
      AppCapability.noteTaking, AppCapability.productivity,
      AppCapability.lectureCompanion,
    ],
    'com.microsoft.office.onenote': [
      AppCapability.noteTaking, AppCapability.productivity,
      AppCapability.lectureCompanion,
    ],
    'notion': [
      AppCapability.noteTaking, AppCapability.productivity,
      AppCapability.lectureCompanion,
    ],
    'evernote': [
      AppCapability.noteTaking, AppCapability.productivity,
    ],
    'obsidian': [
      AppCapability.noteTaking, AppCapability.productivity,
      AppCapability.lectureCompanion,
    ],
    'logseq': [
      AppCapability.noteTaking, AppCapability.productivity,
    ],
    'bear': [
      AppCapability.noteTaking, AppCapability.productivity,
    ],

    // ---------- Office / docs ----------
    'docs.editors.docs': [
      AppCapability.productivity, AppCapability.documentEditing,
      AppCapability.professional,
    ],
    'docs.editors.sheets': [
      AppCapability.productivity, AppCapability.documentEditing,
      AppCapability.professional,
    ],
    'docs.editors.slides': [
      AppCapability.productivity, AppCapability.documentEditing,
      AppCapability.professional,
    ],
    'com.microsoft.office.word': [
      AppCapability.productivity, AppCapability.documentEditing,
      AppCapability.professional,
    ],
    'com.microsoft.office.excel': [
      AppCapability.productivity, AppCapability.documentEditing,
      AppCapability.professional,
    ],
    'com.microsoft.office.powerpoint': [
      AppCapability.productivity, AppCapability.documentEditing,
      AppCapability.professional,
    ],
    'com.adobe.reader': [
      AppCapability.productivity, AppCapability.documentEditing,
      AppCapability.reading,
    ],
    'com.google.android.apps.docs': [ // Drive
      AppCapability.productivity, AppCapability.documentEditing,
    ],

    // ---------- Tasks ----------
    'todoist': [
      AppCapability.tasks, AppCapability.productivity,
      AppCapability.reminders,
    ],
    'ticktick': [
      AppCapability.tasks, AppCapability.productivity,
      AppCapability.reminders,
    ],
    'com.google.android.apps.tasks': [
      AppCapability.tasks, AppCapability.productivity,
      AppCapability.reminders,
    ],
    'asana': [
      AppCapability.projectManagement, AppCapability.productivity,
      AppCapability.professional,
    ],
    'trello': [
      AppCapability.projectManagement, AppCapability.productivity,
    ],
    'linear': [
      AppCapability.projectManagement, AppCapability.productivity,
      AppCapability.professional,
    ],
    'jira': [
      AppCapability.projectManagement, AppCapability.productivity,
      AppCapability.professional,
    ],
    'reminder': [
      AppCapability.reminders, AppCapability.productivity,
    ],

    // ---------- Navigation / commute ----------
    'com.google.android.apps.maps': [
      AppCapability.navigation, AppCapability.location,
      AppCapability.commute, AppCapability.traffic,
    ],
    'com.waze': [
      AppCapability.navigation, AppCapability.location,
      AppCapability.commute, AppCapability.traffic,
    ],
    'com.ubercab': [
      AppCapability.rideshare, AppCapability.commute,
      AppCapability.navigation,
    ],
    'com.lyft': [
      AppCapability.rideshare, AppCapability.commute,
      AppCapability.navigation,
    ],
    'transit': [
      AppCapability.transit, AppCapability.commute,
      AppCapability.navigation,
    ],
    'citymapper': [
      AppCapability.transit, AppCapability.commute,
      AppCapability.navigation,
    ],
    'moovit': [
      AppCapability.transit, AppCapability.commute,
    ],

    // ---------- Music / audio ----------
    'spotify': [
      AppCapability.music, AppCapability.audio,
      AppCapability.entertainment, AppCapability.podcasts,
    ],
    'com.apple.android.music': [
      AppCapability.music, AppCapability.audio, AppCapability.entertainment,
    ],
    'com.google.android.apps.youtube.music': [
      AppCapability.music, AppCapability.audio, AppCapability.entertainment,
    ],
    // Permissive matches catch modded / sideloaded variants like
    // ReVanced (app.revanced.android.apps.youtube.music), Vanced, and
    // re-skinned builds (YT Music Morphe). Substring matching means
    // any package containing 'youtube.music' or 'ytmusic' qualifies.
    'youtube.music': [
      AppCapability.music, AppCapability.audio, AppCapability.entertainment,
      AppCapability.podcasts,
    ],
    'ytmusic': [
      AppCapability.music, AppCapability.audio, AppCapability.entertainment,
    ],
    'pandora': [
      AppCapability.music, AppCapability.audio, AppCapability.entertainment,
    ],
    'soundcloud': [
      AppCapability.music, AppCapability.audio, AppCapability.entertainment,
    ],
    'tidal': [
      AppCapability.music, AppCapability.audio, AppCapability.entertainment,
    ],
    'deezer': [
      AppCapability.music, AppCapability.audio, AppCapability.entertainment,
    ],
    'com.amazon.mp3': [
      AppCapability.music, AppCapability.audio, AppCapability.entertainment,
    ],
    'com.sec.android.app.music': [ // Samsung Music
      AppCapability.music, AppCapability.audio, AppCapability.entertainment,
    ],
    'com.samsung.android.app.music': [ // Samsung Music (alt id)
      AppCapability.music, AppCapability.audio, AppCapability.entertainment,
    ],
    'samsung.music': [ // generic Samsung Music substring
      AppCapability.music, AppCapability.audio, AppCapability.entertainment,
    ],
    'com.android.music': [ // AOSP Music
      AppCapability.music, AppCapability.audio, AppCapability.entertainment,
    ],
    'musicfx': [
      AppCapability.music, AppCapability.audio,
    ],
    'audible': [
      AppCapability.audiobooks, AppCapability.audio, AppCapability.reading,
    ],
    'overcast': [
      AppCapability.podcasts, AppCapability.audio,
    ],
    'pocketcasts': [
      AppCapability.podcasts, AppCapability.audio,
    ],
    'com.google.android.apps.podcasts': [
      AppCapability.podcasts, AppCapability.audio,
    ],
    'castbox': [
      AppCapability.podcasts, AppCapability.audio,
    ],

    // ---------- Video / streaming ----------
    'netflix': [
      AppCapability.video, AppCapability.entertainment,
      AppCapability.streaming,
    ],
    'com.google.android.youtube': [
      AppCapability.video, AppCapability.entertainment,
    ],
    // ReVanced / Vanced / "YouTube Morphe" etc. — any package whose name
    // contains '.youtube' (and isn't already matched by the Music key
    // above, which adds music tags additively rather than excluding).
    '.youtube': [
      AppCapability.video, AppCapability.entertainment,
    ],
    'newpipe': [
      AppCapability.video, AppCapability.entertainment,
    ],
    'libretube': [
      AppCapability.video, AppCapability.entertainment,
    ],
    'hulu': [
      AppCapability.video, AppCapability.entertainment,
      AppCapability.streaming,
    ],
    'disneyplus': [
      AppCapability.video, AppCapability.entertainment,
      AppCapability.streaming,
    ],
    'hbomax': [
      AppCapability.video, AppCapability.entertainment,
      AppCapability.streaming,
    ],
    'primevideo': [
      AppCapability.video, AppCapability.entertainment,
      AppCapability.streaming,
    ],
    'amazon.avod': [
      AppCapability.video, AppCapability.entertainment,
      AppCapability.streaming,
    ],
    'paramountplus': [
      AppCapability.video, AppCapability.entertainment,
      AppCapability.streaming,
    ],
    'twitch': [
      AppCapability.video, AppCapability.entertainment, AppCapability.gaming,
    ],
    'plex': [
      AppCapability.video, AppCapability.entertainment,
    ],

    // ---------- Browser ----------
    'com.android.chrome': [AppCapability.browser, AppCapability.web],
    'org.mozilla': [AppCapability.browser, AppCapability.web],
    'firefox': [AppCapability.browser, AppCapability.web],
    'opera': [AppCapability.browser, AppCapability.web],
    'duckduckgo': [
      AppCapability.browser, AppCapability.web, AppCapability.search,
    ],
    'brave': [AppCapability.browser, AppCapability.web],
    'samsung.android.app.sbrowser': [AppCapability.browser, AppCapability.web],
    'edge': [AppCapability.browser, AppCapability.web],

    // ---------- Camera / photos ----------
    'com.android.camera': [
      AppCapability.camera, AppCapability.photography,
    ],
    'com.google.android.googlecamera': [
      AppCapability.camera, AppCapability.photography,
    ],
    'com.sec.android.app.camera': [
      AppCapability.camera, AppCapability.photography,
    ],
    'com.google.android.apps.photos': [
      AppCapability.gallery, AppCapability.photos,
    ],
    'com.sec.android.gallery3d': [
      AppCapability.gallery, AppCapability.photos,
    ],
    'com.android.gallery3d': [
      AppCapability.gallery, AppCapability.photos,
    ],

    // ---------- Reading ----------
    'kindle': [AppCapability.reading, AppCapability.books],
    'com.amazon.kindle': [AppCapability.reading, AppCapability.books],
    'pocket': [AppCapability.reading, AppCapability.articles],
    'medium': [AppCapability.reading, AppCapability.articles],
    'com.google.android.apps.books': [
      AppCapability.reading, AppCapability.books,
    ],
    'feedly': [AppCapability.reading, AppCapability.news],
    'flipboard': [AppCapability.reading, AppCapability.news],
    'newsbreak': [AppCapability.reading, AppCapability.news],
    'nytimes': [AppCapability.reading, AppCapability.news],
    'wsj': [AppCapability.reading, AppCapability.news],
    'bbc': [AppCapability.reading, AppCapability.news],
    'washingtonpost': [AppCapability.reading, AppCapability.news],
    'apple.news': [AppCapability.reading, AppCapability.news],
    'google.android.apps.magazines': [
      AppCapability.reading, AppCapability.news,
    ],

    // ---------- Social ----------
    'instagram': [
      AppCapability.social, AppCapability.entertainment,
      AppCapability.photoSharing,
    ],
    'twitter': [AppCapability.social, AppCapability.news],
    'com.x.': [AppCapability.social, AppCapability.news],
    'facebook.katana': [AppCapability.social],
    'facebook.orca': [
      AppCapability.social, AppCapability.communication,
      AppCapability.messaging,
    ],
    'snapchat': [
      AppCapability.social, AppCapability.messaging,
      AppCapability.entertainment,
    ],
    'tiktok': [
      AppCapability.social, AppCapability.entertainment, AppCapability.video,
    ],
    'reddit': [
      AppCapability.social, AppCapability.reading, AppCapability.news,
    ],
    'pinterest': [
      AppCapability.social, AppCapability.inspiration,
      AppCapability.discovery,
    ],
    'tumblr': [AppCapability.social, AppCapability.entertainment],
    'threads': [AppCapability.social],
    'linkedin': [AppCapability.social, AppCapability.professional],
    'bsky.app': [AppCapability.social],
    'mastodon': [AppCapability.social],

    // ---------- Health / fitness ----------
    'com.google.android.apps.fitness': [
      AppCapability.fitness, AppCapability.health,
    ],
    'strava': [
      AppCapability.fitness, AppCapability.health, AppCapability.running,
    ],
    'runkeeper': [
      AppCapability.fitness, AppCapability.health, AppCapability.running,
    ],
    'nike.plusgps': [
      AppCapability.fitness, AppCapability.health, AppCapability.running,
    ],
    'myfitnesspal': [
      AppCapability.fitness, AppCapability.health, AppCapability.nutrition,
    ],
    'fitbit': [AppCapability.fitness, AppCapability.health],
    'samsung.health': [AppCapability.fitness, AppCapability.health],
    'samsung.android.shealth': [AppCapability.fitness, AppCapability.health],
    'headspace': [
      AppCapability.meditation, AppCapability.health, AppCapability.sleepTools,
      AppCapability.windDown,
    ],
    'calm': [
      AppCapability.meditation, AppCapability.health, AppCapability.sleepTools,
      AppCapability.windDown,
    ],
    'sleeptracker': [
      AppCapability.sleepTools, AppCapability.health,
    ],

    // ---------- Money / banking ----------
    'paypal': [AppCapability.banking, AppCapability.finance],
    'venmo': [AppCapability.banking, AppCapability.finance],
    'cashapp': [AppCapability.banking, AppCapability.finance],
    'zelle': [AppCapability.banking, AppCapability.finance],
    'bank': [AppCapability.banking, AppCapability.finance],
    'banking': [AppCapability.banking, AppCapability.finance],
    'wellsfargo': [AppCapability.banking, AppCapability.finance],
    'chase.sig.android': [AppCapability.banking, AppCapability.finance],
    'usaa': [AppCapability.banking, AppCapability.finance],
    'mint': [AppCapability.finance],
    'robinhood': [AppCapability.finance],
    'coinbase': [AppCapability.finance],
    'google.android.apps.walletnfcrel': [AppCapability.payments],
    'google.android.apps.wallet': [AppCapability.payments],

    // ---------- Food / delivery ----------
    'doordash': [AppCapability.food, AppCapability.delivery],
    'ubereats': [AppCapability.food, AppCapability.delivery],
    'grubhub': [AppCapability.food, AppCapability.delivery],
    'postmates': [AppCapability.food, AppCapability.delivery],
    'yelp': [
      AppCapability.food, AppCapability.restaurants, AppCapability.discovery,
    ],
    'opentable': [AppCapability.food, AppCapability.restaurants],
    'starbucks': [AppCapability.food],
    'mcdonalds': [AppCapability.food],
    'chickfila': [AppCapability.food],

    // ---------- Shopping ----------
    'amazon.mShop': [AppCapability.shopping],
    'com.amazon.mshop': [AppCapability.shopping],
    'ebay': [AppCapability.shopping],
    'target': [AppCapability.shopping],
    'walmart': [AppCapability.shopping],
    'bestbuy': [AppCapability.shopping],
    'etsy': [AppCapability.shopping],
    'shop.app': [AppCapability.shopping],

    // ---------- Travel / weather ----------
    'tripadvisor': [AppCapability.travel],
    'airbnb': [AppCapability.travel],
    'booking': [AppCapability.travel, AppCapability.flights],
    'expedia': [AppCapability.travel, AppCapability.flights],
    'kayak': [AppCapability.travel, AppCapability.flights],
    'flighty': [AppCapability.travel, AppCapability.flights],
    'tripit': [AppCapability.travel],
    'weather': [AppCapability.weather],
    'accuweather': [AppCapability.weather],
    'darksky': [AppCapability.weather],

    // ---------- Security / utilities ----------
    'com.google.android.apps.authenticator': [
      AppCapability.authentication, AppCapability.security,
    ],
    'authy': [AppCapability.authentication, AppCapability.security],
    '1password': [
      AppCapability.passwords, AppCapability.security,
      AppCapability.authentication,
    ],
    'lastpass': [
      AppCapability.passwords, AppCapability.security,
      AppCapability.authentication,
    ],
    'bitwarden': [
      AppCapability.passwords, AppCapability.security,
      AppCapability.authentication,
    ],

    // ---------- System utilities ----------
    'com.android.settings': [AppCapability.settings, AppCapability.system],
    'com.samsung.android.lool': [AppCapability.settings, AppCapability.system],
    'com.android.deskclock': [
      AppCapability.clock, AppCapability.alarm, AppCapability.timer,
    ],
    'com.sec.android.app.clockpackage': [
      AppCapability.clock, AppCapability.alarm, AppCapability.timer,
    ],
    'com.google.android.deskclock': [
      AppCapability.clock, AppCapability.alarm, AppCapability.timer,
    ],
    'com.android.calculator': [
      AppCapability.calculator, AppCapability.utility,
    ],
    'com.sec.android.app.popupcalculator': [
      AppCapability.calculator, AppCapability.utility,
    ],
    'com.google.android.calculator': [
      AppCapability.calculator, AppCapability.utility,
    ],
  };

  /// Built-in capability tags for [packageName].
  /// Returns an empty list if no pattern matches.
  static List<String> tagsFor(String packageName) {
    final override = _userOverrides[packageName];
    if (override != null) return override;

    final lower = packageName.toLowerCase();
    final tags = <String>{};
    for (final entry in _patterns.entries) {
      if (lower.contains(entry.key.toLowerCase())) {
        tags.addAll(entry.value);
      }
    }
    return tags.toList(growable: false);
  }

  /// True iff [packageName] has at least one known capability tag.
  static bool isKnown(String packageName) => tagsFor(packageName).isNotEmpty;

  /// Override the capability tags for a specific package at runtime.
  /// Pass an empty list to suppress the app from ever being recommended
  /// (it will match no need); pass `null` to remove the override.
  static void registerOverride(String packageName, List<String>? tags) {
    if (tags == null) {
      _userOverrides.remove(packageName);
    } else {
      _userOverrides[packageName] = List.unmodifiable(tags);
    }
  }

  static void clearOverrides() => _userOverrides.clear();
}
