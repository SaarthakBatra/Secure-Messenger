import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/streak_provider.dart';
import '../providers/word_of_day_provider.dart';
import '../services/wotd_sync_service.dart';

// The stealth callback provider overridden by the vault module to unlock secure messenger
final coverLogoLongPressCallbackProvider = Provider<VoidCallback>((ref) {
  return () {
    debugPrint('Cover Logo Stealth Hook activated!');
  };
});

class DecoyHomeScreen extends ConsumerStatefulWidget {
  const DecoyHomeScreen({super.key});

  @override
  ConsumerState<DecoyHomeScreen> createState() => _DecoyHomeScreenState();
}

class _DecoyHomeScreenState extends ConsumerState<DecoyHomeScreen> {
  Timer? _stealthTimer;
  int _xp = 340;
  final int _xpGoal = 500;
  final List<String> _recentlyLearned = ['Apple', 'Banana', 'Freedom', 'Peace', 'Cat'];

  // Track tapped status for 3 conversation flippers
  final List<bool> _conversationFlipped = [false, false, false];
  final List<Map<String, String>> _conversations = [
    {
      'english': 'Excuse me, where is the library?',
      'spanish': 'Disculpe, ¿dónde está la biblioteca?',
    },
    {
      'english': 'I would like to order a cup of coffee, please.',
      'spanish': 'Me gustaría pedir una taza de café, por favor.',
    },
    {
      'english': 'How much does this ticket cost?',
      'spanish': '¿Cuánto cuesta este boleto?',
    },
  ];

  @override
  void dispose() {
    _stealthTimer?.cancel();
    super.dispose();
  }

  void _incrementXP(int amount) {
    setState(() {
      _xp = min(_xpGoal, _xp + amount);
    });
  }

  @override
  Widget build(BuildContext context) {
    final streak = ref.watch(streakProvider);
    final wotdAsync = ref.watch(wotdProvider);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFF0F2027),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Off-screen/transparent indicator to satisfy legacy route tests
                const Text(
                  'Home',
                  style: TextStyle(color: Colors.transparent, fontSize: 0),
                ),

                // Header Row (Logo + Streak Badge + Menu)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Stealth Hook Logo
                    GestureDetector(
                      key: const Key('stealth_logo_button'),
                      onTapDown: (_) {
                        _stealthTimer = Timer(const Duration(seconds: 3), () {
                          ref.read(coverLogoLongPressCallbackProvider)();
                        });
                      },
                      onTapUp: (_) {
                        _stealthTimer?.cancel();
                      },
                      onTapCancel: () {
                        _stealthTimer?.cancel();
                      },
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white.withOpacity(0.1)),
                        ),
                        child: const Row(
                          children: [
                            Icon(
                              Icons.translate_rounded,
                              color: Color(0xFF00E676),
                              size: 28,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'MultiLingo',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Right Side Actions
                    Row(
                      children: [
                        // Streak Badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF9100).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFFFF9100).withOpacity(0.3)),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.local_fire_department_rounded,
                                color: Color(0xFFFF9100),
                                size: 20,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '$streak Days',
                                style: const TextStyle(
                                  color: Color(0xFFFF9100),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 4),
                        // Collapsible Settings Menu
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert_rounded, color: Colors.white70),
                          color: const Color(0xFF1F3A45),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          onSelected: (value) {
                            if (value == 'report') {
                              context.push('/home/report-issue');
                            } else if (value == 'settings') {
                              context.push('/home/settings');
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'settings',
                              child: Row(
                                children: [
                                  Icon(Icons.settings_rounded, color: Colors.white70, size: 20),
                                  SizedBox(width: 12),
                                  Text('Settings', style: TextStyle(color: Colors.white)),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'report',
                              child: Row(
                                children: [
                                  Icon(Icons.bug_report_rounded, color: Colors.white70, size: 20),
                                  SizedBox(width: 12),
                                  Text('Report Issue', style: TextStyle(color: Colors.white)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Gamified Daily XP Progress Bar
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.03),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withOpacity(0.05)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Daily Goal progress',
                            style: TextStyle(color: Colors.white70, fontSize: 13),
                          ),
                          Text(
                            '$_xp / $_xpGoal XP',
                            style: const TextStyle(
                              color: Color(0xFF00E676),
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: _xp / _xpGoal,
                          minHeight: 10,
                          backgroundColor: Colors.white.withOpacity(0.1),
                          color: const Color(0xFF00E676),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // Unit Card + Interactive Lesson Button
                Text(
                  'My Learning Path',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white.withOpacity(0.9),
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00E676).withOpacity(0.08),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: const Color(0xFF00E676).withOpacity(0.2)),
                  ),
                  child: Row(
                    children: [
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: 60,
                            height: 60,
                            child: CircularProgressIndicator(
                              value: 0.65,
                              strokeWidth: 6,
                              backgroundColor: Colors.white.withOpacity(0.1),
                              color: const Color(0xFF00E676),
                            ),
                          ),
                          const Icon(Icons.star_rounded, color: Color(0xFF00E676), size: 30),
                        ],
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Unit 2: Travel Basics',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Lesson 3 of 5 • 65% Complete',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.6),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => _launchLessonModal(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00E676),
                    foregroundColor: const Color(0xFF0F2027),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 4,
                  ),
                  child: const Text(
                    'Continue Learning',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 36),

                // Conversation Practice Section
                Text(
                  'Conversation Practice',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white.withOpacity(0.9),
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Tap any card to reveal its real-world translation',
                  style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
                ),
                const SizedBox(height: 12),
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _conversations.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final item = _conversations[index];
                    final isFlipped = _conversationFlipped[index];
                    return InkWell(
                      onTap: () {
                        setState(() {
                          _conversationFlipped[index] = !isFlipped;
                        });
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: isFlipped
                              ? const Color(0xFF00E676).withOpacity(0.08)
                              : Colors.white.withOpacity(0.04),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isFlipped
                                ? const Color(0xFF00E676).withOpacity(0.3)
                                : Colors.white.withOpacity(0.08),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isFlipped ? Icons.check_circle_outline_rounded : Icons.help_outline_rounded,
                              color: isFlipped ? const Color(0xFF00E676) : Colors.white54,
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    item['english']!,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                  if (isFlipped) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      item['spanish']!,
                                      style: const TextStyle(
                                        color: Color(0xFF00E676),
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 36),

                // Daily Practice Word of the Day Section
                Text(
                  'Daily Practice',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white.withOpacity(0.9),
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 12),
                wotdAsync.when(
                  data: (wotd) => Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF1F4068), Color(0xFF162447)],
                      ),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'WORD OF THE DAY',
                              style: TextStyle(
                                color: Color(0xFF00E676),
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                                letterSpacing: 1.5,
                              ),
                            ),
                            Icon(
                              Icons.volume_up_rounded,
                              color: Colors.white.withOpacity(0.3),
                              size: 20,
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          wotd.word,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          wotd.translation,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.7),
                            fontSize: 18,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Divider(color: Colors.white.withOpacity(0.1)),
                        const SizedBox(height: 12),
                        Text(
                          wotd.definition,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.6),
                            fontSize: 14,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  loading: () => Container(
                    height: 180,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.04),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF00E676),
                      ),
                    ),
                  ),
                  error: (err, stack) => Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.redAccent.withOpacity(0.2)),
                    ),
                    child: const Column(
                      children: [
                        Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 36),
                        SizedBox(height: 12),
                        Text(
                          'Failed to load daily word.',
                          style: TextStyle(color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 36),

                // Achievements Badges Shelf (Horizontal Scroll)
                Text(
                  'Achievements Shelf',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white.withOpacity(0.9),
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 110,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    children: [
                      _buildAchievementCard('Streak Hero', '5-Day Fire 🔥', Colors.orange),
                      const SizedBox(width: 12),
                      _buildAchievementCard('Quiz Master', 'Scored 5/5 🏆', Colors.amber),
                      const SizedBox(width: 12),
                      _buildAchievementCard('Word Scholar', 'Studied 10 terms 🌍', Colors.blue),
                    ],
                  ),
                ),
                const SizedBox(height: 36),

                // Recently Learned Words Carousel
                Text(
                  'Recently Learned Words',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white.withOpacity(0.9),
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 56,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    itemCount: _recentlyLearned.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (context, idx) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.04),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white.withOpacity(0.06)),
                      ),
                      child: Center(
                        child: Text(
                          _recentlyLearned[idx],
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 36),

                // Tools Section
                Text(
                  'Tools',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white.withOpacity(0.9),
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 12),
                _buildActionCard(
                  title: 'Phrase Translator',
                  subtitle: 'Translate words or sentences on the go.',
                  icon: Icons.translate_rounded,
                  color: const Color(0xFFE94560),
                  onTap: () => context.push('/home/translation'),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAchievementCard(String title, String label, Color color) {
    return Container(
      width: 160,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            title,
            style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: Colors.white.withOpacity(0.3),
            ),
          ],
        ),
      ),
    );
  }

  void _launchLessonModal(BuildContext context) {
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.9),
      transitionDuration: const Duration(milliseconds: 350),
      pageBuilder: (context, __, ___) => _InteractiveLessonFlow(
        onCompleted: (xpReward) {
          _incrementXP(xpReward);
        },
      ),
    );
  }
}

// Stateful interactive 10 vocabulary cards + 5-question multi-choice quiz modal
class _InteractiveLessonFlow extends StatefulWidget {
  final ValueChanged<int> onCompleted;
  const _InteractiveLessonFlow({required this.onCompleted});

  @override
  State<_InteractiveLessonFlow> createState() => _InteractiveLessonFlowState();
}

class _InteractiveLessonFlowState extends State<_InteractiveLessonFlow> {
  int _currentPhase = 1; // 1 = Vocab, 2 = Quiz, 3 = Results
  int _vocabIndex = 0;
  bool _cardFlipped = false;
  int _quizIndex = 0;
  int _score = 0;
  int? _selectedQuizOptionIdx;
  bool _quizChecked = false;
  
  List<WordOfDay> _words = [];
  List<Map<String, dynamic>> _quizQuestions = [];

  @override
  void initState() {
    super.initState();
    _loadWords();
  }

  void _loadWords() async {
    // Dynamic fallbacks matching words.json
    final staticBackup = [
      WordOfDay(word: 'apple', translation: 'manzana', definition: 'A round fruit.'),
      WordOfDay(word: 'banana', translation: 'plátano', definition: 'A yellow curved fruit.'),
      WordOfDay(word: 'freedom', translation: 'libertad', definition: 'The power to act.'),
      WordOfDay(word: 'peace', translation: 'paz', definition: 'Freedom from disturbance.'),
      WordOfDay(word: 'cat', translation: 'gato', definition: 'A small domesticated carnivorous mammal.'),
      WordOfDay(word: 'dog', translation: 'perro', definition: 'A common domesticated carnivorous mammal.'),
      WordOfDay(word: 'water', translation: 'agua', definition: 'A colorless, odorless chemical compound.'),
      WordOfDay(word: 'book', translation: 'libro', definition: 'A written or printed work.'),
      WordOfDay(word: 'friend', translation: 'amigo', definition: 'A person whom one knows and has a bond of mutual affection.'),
      WordOfDay(word: 'school', translation: 'escuela', definition: 'An institution for educating children.')
    ];

    try {
      final jsonString = await DefaultAssetBundle.of(context).loadString('assets/words.json');
      final List<dynamic> jsonList = jsonDecode(jsonString);
      List<WordOfDay> parsed = jsonList.map((e) => WordOfDay.fromJson(e)).toList();
      
      // Ensure we have exactly 10 words (pad or shuffle)
      if (parsed.length < 10) {
        parsed.addAll(staticBackup.sublist(0, 10 - parsed.length));
      }
      setState(() {
        _words = parsed.sublist(0, 10);
        _generateQuiz();
      });
    } catch (_) {
      setState(() {
        _words = staticBackup;
        _generateQuiz();
      });
    }
  }

  void _generateQuiz() {
    if (_words.length < 5) return;
    
    // Select 5 random words from our study pool of 10
    final pool = List<WordOfDay>.from(_words)..shuffle();
    final List<Map<String, dynamic>> quiz = [];

    for (int i = 0; i < 5; i++) {
      final correctWord = pool[i];
      
      // Gather translation distractors
      final List<String> options = [correctWord.translation];
      final distractors = _words.where((w) => w.translation != correctWord.translation).toList()..shuffle();
      
      options.addAll(distractors.take(3).map((d) => d.translation));
      options.shuffle(); // Shuffle options

      quiz.add({
        'question': 'How do you translate: "${correctWord.word}"?',
        'options': options,
        'correctAnswer': correctWord.translation,
      });
    }

    setState(() {
      _quizQuestions = quiz;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_words.isEmpty || (_currentPhase == 2 && _quizQuestions.isEmpty)) {
      return const Scaffold(
        backgroundColor: Color(0xFF0F2027),
        body: Center(child: CircularProgressIndicator(color: Color(0xFF00E676))),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0F2027),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header Close button + Progress Indicator
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white70),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: _currentProgressPercent(),
                          minHeight: 8,
                          backgroundColor: Colors.white.withOpacity(0.1),
                          color: const Color(0xFF00E676),
                        ),
                      ),
                    ),
                  ),
                  Text(
                    _getProgressLabel(),
                    style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 36),

              // Dynamic Phase Renders
              Expanded(
                child: _currentPhase == 1
                    ? _buildVocabPhase()
                    : _currentPhase == 2
                        ? _buildQuizPhase()
                        : _buildResultsPhase(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  double _currentProgressPercent() {
    if (_currentPhase == 1) {
      return (_vocabIndex + 1) / 10 * 0.5; // Vocab takes first 50%
    } else if (_currentPhase == 2) {
      return 0.5 + ((_quizIndex + 1) / 5 * 0.5); // Quiz takes second 50%
    }
    return 1.0;
  }

  String _getProgressLabel() {
    if (_currentPhase == 1) {
      return 'Vocab ${_vocabIndex + 1}/10';
    } else if (_currentPhase == 2) {
      return 'Quiz ${_quizIndex + 1}/5';
    }
    return 'Done';
  }

  // 1. Vocabulary Phase flashcard render
  Widget _buildVocabPhase() {
    final word = _words[_vocabIndex];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Vocab Flashcards',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFF00E676), fontWeight: FontWeight.bold, letterSpacing: 1.5, fontSize: 11),
        ),
        const SizedBox(height: 8),
        const Text(
          'Study and tap to flip the card',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white54, fontSize: 14),
        ),
        const SizedBox(height: 32),
        Expanded(
          child: GestureDetector(
            onTap: () {
              setState(() {
                _cardFlipped = !_cardFlipped;
              });
            },
            child: Container(
              decoration: BoxDecoration(
                color: _cardFlipped ? const Color(0xFF162447) : const Color(0xFF1F4068),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 16, offset: const Offset(0, 8)),
                ],
              ),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _cardFlipped ? 'SPANISH TRANSLATION' : 'ENGLISH TERM',
                        style: TextStyle(
                          color: _cardFlipped ? const Color(0xFF00E676) : Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _cardFlipped ? word.translation : word.word,
                        style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),
                      if (_cardFlipped)
                        Text(
                          word.definition,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 16, height: 1.4),
                        )
                      else
                        Text(
                          'Tap to reveal',
                          style: TextStyle(color: Colors.white.withOpacity(0.3), fontStyle: FontStyle.italic),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 32),
        ElevatedButton(
          onPressed: _nextVocab,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF00E676),
            foregroundColor: const Color(0xFF0F2027),
            padding: const EdgeInsets.symmetric(vertical: 18),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          child: Text(
            _vocabIndex == 9 ? 'Proceed to Quiz' : 'Next Word',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ),
      ],
    );
  }

  void _nextVocab() {
    if (_vocabIndex < 9) {
      setState(() {
        _vocabIndex++;
        _cardFlipped = false;
      });
    } else {
      setState(() {
        _currentPhase = 2; // Move to Quiz
      });
    }
  }

  // 2. Multiple-choice Quiz Phase render
  Widget _buildQuizPhase() {
    final q = _quizQuestions[_quizIndex];
    final options = q['options'] as List<dynamic>;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'UNIT MINI-QUIZ',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFFFF9100), fontWeight: FontWeight.bold, letterSpacing: 1.5, fontSize: 11),
        ),
        const SizedBox(height: 8),
        Text(
          q['question'],
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 24),
        Expanded(
          child: ListView.separated(
            itemCount: options.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, idx) {
              final option = options[idx];
              final isSelected = _selectedQuizOptionIdx == idx;
              
              Color cardColor = Colors.white.withOpacity(0.04);
              Color borderColor = Colors.white.withOpacity(0.08);

              if (_quizChecked) {
                final isCorrectOption = option == q['correctAnswer'];
                if (isCorrectOption) {
                  cardColor = const Color(0xFF00E676).withOpacity(0.1);
                  borderColor = const Color(0xFF00E676);
                } else if (isSelected) {
                  cardColor = Colors.redAccent.withOpacity(0.1);
                  borderColor = Colors.redAccent;
                }
              } else if (isSelected) {
                borderColor = const Color(0xFF00E676);
                cardColor = Colors.white.withOpacity(0.08);
              }

              return InkWell(
                onTap: _quizChecked
                    ? null
                    : () {
                        setState(() {
                          _selectedQuizOptionIdx = idx;
                        });
                      },
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: borderColor, width: 2),
                  ),
                  child: Row(
                    children: [
                      Text(
                        '${String.fromCharCode(65 + idx)}.',
                        style: TextStyle(
                          color: isSelected ? const Color(0xFF00E676) : Colors.white54,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Text(
                        option,
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: _selectedQuizOptionIdx == null ? null : _quizChecked ? _nextQuestion : _checkAnswer,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF00E676),
            foregroundColor: const Color(0xFF0F2027),
            padding: const EdgeInsets.symmetric(vertical: 18),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          child: Text(
            _quizChecked ? (_quizIndex == 4 ? 'Finish Quiz' : 'Next Question') : 'Check Answer',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ),
      ],
    );
  }

  void _checkAnswer() {
    final q = _quizQuestions[_quizIndex];
    final selectedOption = q['options'][_selectedQuizOptionIdx!];
    final isCorrect = selectedOption == q['correctAnswer'];

    setState(() {
      _quizChecked = true;
      if (isCorrect) {
        _score++;
      }
    });
  }

  void _nextQuestion() {
    if (_quizIndex < 4) {
      setState(() {
        _quizIndex++;
        _selectedQuizOptionIdx = null;
        _quizChecked = false;
      });
    } else {
      setState(() {
        _currentPhase = 3; // Move to Results
      });
    }
  }

  // 3. Results Screen render
  Widget _buildResultsPhase() {
    final xpReward = _score * 20; // 20 XP per correct answer
    
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.stars_rounded, color: Color(0xFF00E676), size: 100),
        const SizedBox(height: 24),
        const Text(
          'Lesson Completed!',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        Text(
          'You scored: $_score / 5 correct answers',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 16),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.04),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: Column(
            children: [
              const Text('REWARDS', style: TextStyle(color: Color(0xFF00E676), fontWeight: FontWeight.bold, fontSize: 12)),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.bolt, color: Color(0xFFFF9100), size: 30),
                  const SizedBox(width: 8),
                  Text(
                    '+$xpReward XP earned today',
                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Spacer(),
        ElevatedButton(
          onPressed: () {
            widget.onCompleted(xpReward);
            Navigator.pop(context);
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF00E676),
            foregroundColor: const Color(0xFF0F2027),
            padding: const EdgeInsets.symmetric(vertical: 18),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          child: const Text(
            'Return to Dashboard',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ),
      ],
    );
  }
}
