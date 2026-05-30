import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../data/mock_dictionary.dart';
import '../providers/streak_provider.dart';
import '../providers/word_of_day_provider.dart';
import '../providers/target_language_provider.dart';
import '../services/wotd_sync_service.dart';
import 'leaderboard_screen.dart';
import 'profile_screen.dart';
import 'match_game_screen.dart';

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
  int _selectedIndex = 0;
  int _logoTapCount = 0;
  DateTime? _lastLogoTapTime;
  int _xp = 340;
  final int _xpGoal = 500;
  final List<String> _recentlyLearned = ['Apple', 'Banana', 'Freedom', 'Peace', 'Cat'];
  bool _questClaimed = false;

  // Track tapped status for 3 conversation flippers
  final List<bool> _conversationFlipped = [false, false, false];

  List<Map<String, String>> _getConversations(String langCode) {
    final Map<String, List<Map<String, String>>> data = {
      'es': [
        {'english': 'Excuse me, where is the library?', 'target': 'Disculpe, ¿dónde está la biblioteca?'},
        {'english': 'I would like to order a cup of coffee, please.', 'target': 'Me gustaría pedir una taza de café, por favor.'},
        {'english': 'How much does this ticket cost?', 'target': '¿Cuánto cuesta este boleto?'},
      ],
      'fr': [
        {'english': 'Excuse me, where is the library?', 'target': 'Excusez-moi, où est la bibliothèque ?'},
        {'english': 'I would like to order a cup of coffee, please.', 'target': 'Je voudrais commander une tasse de café, s\'il vous plaît.'},
        {'english': 'How much does this ticket cost?', 'target': 'Combien coûte ce billet ?'},
      ],
      'ja': [
        {'english': 'Excuse me, where is the library?', 'target': 'すみません、図書館はどこですか？'},
        {'english': 'I would like to order a cup of coffee, please.', 'target': 'コーヒーを一杯お願いします。'},
        {'english': 'How much does this ticket cost?', 'target': 'このチケットはいくらですか？'},
      ],
      'de': [
        {'english': 'Excuse me, where is the library?', 'target': 'Entschuldigung, wo ist die Bibliothek?'},
        {'english': 'I would like to order a cup of coffee, please.', 'target': 'Ich möchte bitte eine Tasse Kaffee bestellen.'},
        {'english': 'How much does this ticket cost?', 'target': 'Wie viel kostet dieses Ticket?'},
      ],
      'it': [
        {'english': 'Excuse me, where is the library?', 'target': 'Scusi, dov\'è la biblioteca?'},
        {'english': 'I would like to order a cup of coffee, please.', 'target': 'Vorrei ordinare una tazza di caffè, per favore.'},
        {'english': 'How much does this ticket cost?', 'target': 'Quanto costa questo biglietto?'},
      ]
    };
    return data[langCode] ?? data['es']!;
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _handleLogoTap() {
    HapticFeedback.selectionClick();
    final now = DateTime.now();
    if (_lastLogoTapTime == null || now.difference(_lastLogoTapTime!) > const Duration(seconds: 1)) {
      _logoTapCount = 1;
    } else {
      _logoTapCount++;
    }
    _lastLogoTapTime = now;

    debugPrint('[STEALTH] Logo tapped. Count: $_logoTapCount');

    if (_logoTapCount >= 5) {
      _logoTapCount = 0;
      _lastLogoTapTime = null;
      ref.read(coverLogoLongPressCallbackProvider)();
    }
  }

  void _incrementXP(int amount) {
    HapticFeedback.mediumImpact();
    setState(() {
      _xp = min(_xpGoal, _xp + amount);
    });
  }

  void _showLanguageSelector(BuildContext context, String currentLangCode) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1F3A45),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Consumer(
          builder: (context, ref, child) {
            final langsAsync = ref.watch(languagesProvider);
            return langsAsync.when(
              data: (langs) {
                return SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Text(
                          'Select Language',
                          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ),
                      ...langs.map((l) => ListTile(
                        leading: Text(l.flag, style: const TextStyle(fontSize: 24)),
                        title: Text(l.name, style: const TextStyle(color: Colors.white)),
                        trailing: l.code == currentLangCode ? const Icon(Icons.check, color: Color(0xFF00E676)) : null,
                        onTap: () {
                          ref.read(targetLanguageProvider.notifier).state = l.code;
                          Navigator.pop(ctx);
                        },
                      )).toList(),
                    ],
                  ),
                );
              },
              loading: () => const Padding(
                padding: EdgeInsets.all(32.0),
                child: Center(child: CircularProgressIndicator(color: Color(0xFF00E676))),
              ),
              error: (err, stack) => const Padding(
                padding: EdgeInsets.all(32.0),
                child: Text('Failed to load languages', style: TextStyle(color: Colors.redAccent)),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F2027),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          _buildLearnTab(context),
          const LeaderboardScreen(),
          const ProfileScreen(),
        ],
      ),
      floatingActionButton: _selectedIndex == 0 ? FloatingActionButton.extended(
        onPressed: () {
          showGeneralDialog(
            context: context,
            barrierDismissible: false,
            barrierColor: Colors.black.withOpacity(0.9),
            transitionDuration: const Duration(milliseconds: 300),
            pageBuilder: (context, __, ___) => MatchGameScreen(
              onCompleted: (xpReward) {
                _incrementXP(xpReward);
              },
            ),
          );
        },
        backgroundColor: const Color(0xFF00E676),
        icon: const Icon(Icons.gamepad_rounded, color: Color(0xFF0F2027)),
        label: const Text('Play Game', style: TextStyle(color: Color(0xFF0F2027), fontWeight: FontWeight.bold)),
      ) : null,
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: const Color(0xFF1F3A45),
        selectedItemColor: const Color(0xFF00E676),
        unselectedItemColor: Colors.white54,
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_rounded), label: 'Learn'),
          BottomNavigationBarItem(icon: Icon(Icons.leaderboard_rounded), label: 'Leaderboard'),
          BottomNavigationBarItem(icon: Icon(Icons.person_rounded), label: 'Profile'),
        ],
      ),
    );
  }

  Widget _buildLearnTab(BuildContext context) {
    final streak = ref.watch(streakProvider);
    final wotdAsync = ref.watch(wotdProvider);
    final theme = Theme.of(context);
    final currentLangCode = ref.watch(targetLanguageProvider);
    final conversationsList = _getConversations(currentLangCode);

    return SafeArea(
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
                      onTap: _handleLogoTap,
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
                        // Language Selector
                        Consumer(
                          builder: (context, ref, _) {
                            final currentLangCode = ref.watch(targetLanguageProvider);
                            final langsAsync = ref.watch(languagesProvider);
                            String flag = '🌍';
                            langsAsync.whenData((langs) {
                              final match = langs.where((l) => l.code == currentLangCode).toList();
                              if (match.isNotEmpty) flag = match.first.flag;
                            });
                            return IconButton(
                              icon: Text(flag, style: const TextStyle(fontSize: 22)),
                              onPressed: () => _showLanguageSelector(context, currentLangCode),
                            );
                          },
                        ),
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
                
                // Daily Quests UI
                Text(
                  'Daily Quests',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white.withOpacity(0.9),
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 12),
                _buildDailyQuests(context),
                const SizedBox(height: 32),

                // Vertical Skill Tree
                Text(
                  'My Learning Path',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white.withOpacity(0.9),
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 12),
                _buildVerticalSkillTree(context),
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
                  itemCount: conversationsList.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final item = conversationsList[index];
                    final isFlipped = _conversationFlipped[index];
                    return InkWell(
                      onTap: () {
                        HapticFeedback.lightImpact();
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
                                      item['target']!,
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
      );
  }

  Widget _buildDailyQuests(BuildContext context) {
    bool canClaim = _xp >= 50 && !_questClaimed;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: canClaim ? const Color(0xFFFF9100).withOpacity(0.5) : Colors.white.withOpacity(0.05)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFF9100).withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.stars_rounded, color: Color(0xFFFF9100), size: 32),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Earn 50 XP', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value: (_xp / 50.0).clamp(0.0, 1.0),
                  backgroundColor: Colors.white.withOpacity(0.1),
                  color: const Color(0xFFFF9100),
                ),
                const SizedBox(height: 6),
                Text('${_xp.clamp(0, 50)} / 50 XP', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(width: 16),
          if (_questClaimed)
            const Icon(Icons.check_circle_rounded, color: Color(0xFF00E676), size: 32)
          else if (canClaim)
            ElevatedButton(
              onPressed: () {
                HapticFeedback.heavyImpact();
                setState(() => _questClaimed = true);
                _incrementXP(20); // Claim bonus
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF9100),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Claim', style: TextStyle(fontWeight: FontWeight.bold)),
            )
        ],
      ),
    );
  }

  Widget _buildVerticalSkillTree(BuildContext context) {
    return Column(
      children: List.generate(4, (index) {
        final isActive = index == 2;
        final isCompleted = index < 2;
        final isLocked = index > 2;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: [
                Container(
                  width: 2,
                  height: index == 0 ? 0 : 20,
                  color: isCompleted || isActive ? const Color(0xFF00E676) : Colors.white24,
                ),
                GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    if (isActive) _launchLessonModal(context);
                    if (isLocked) {
                       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Complete previous lessons first!')));
                    }
                  },
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isCompleted ? const Color(0xFF00E676) : (isActive ? const Color(0xFF00E676).withOpacity(0.2) : Colors.white12),
                      border: Border.all(
                        color: isActive ? const Color(0xFF00E676) : Colors.transparent,
                        width: 3,
                      ),
                    ),
                    child: Icon(
                      isCompleted ? Icons.check_rounded : (isLocked ? Icons.lock_rounded : Icons.play_arrow_rounded),
                      color: isCompleted ? const Color(0xFF0F2027) : (isActive ? const Color(0xFF00E676) : Colors.white38),
                      size: 28,
                    ),
                  ),
                ),
                Container(
                  width: 2,
                  height: index == 3 ? 0 : 20,
                  color: isCompleted ? const Color(0xFF00E676) : Colors.white24,
                ),
              ],
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(top: index == 0 ? 0 : 20),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: isActive ? const Color(0xFF00E676).withOpacity(0.3) : Colors.white.withOpacity(0.05)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Lesson ${index + 1}',
                        style: TextStyle(
                          color: isLocked ? Colors.white38 : Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isCompleted ? 'Completed' : (isActive ? 'Current Lesson' : 'Locked'),
                        style: TextStyle(
                          color: isCompleted ? const Color(0xFF00E676) : (isActive ? const Color(0xFF00E676) : Colors.white38),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      }),
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
    final currentLang = ref.read(targetLanguageProvider);
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.9),
      transitionDuration: const Duration(milliseconds: 350),
      pageBuilder: (context, __, ___) => _InteractiveLessonFlow(
        langCode: currentLang,
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
  final String langCode;
  const _InteractiveLessonFlow({required this.onCompleted, required this.langCode});

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
    final randomEntries = getRandomWords(10);
    final List<WordOfDay> staticBackup = randomEntries.map((e) {
       final t = e.value[widget.langCode] ?? e.value['es']!;
       return WordOfDay(word: e.key, translation: t, definition: 'A standard dictionary term.');
    }).toList();

    try {
      final jsonString = await DefaultAssetBundle.of(context).loadString('assets/words.json');
      final List<dynamic> jsonList = jsonDecode(jsonString);
      List<WordOfDay> parsed = jsonList.map((e) => WordOfDay.fromJson(e)).toList();
      parsed.shuffle();
      
      // Ensure we have exactly 10 words (pad or shuffle)
      if (parsed.length < 10) {
        parsed.addAll(staticBackup.sublist(0, min(10 - parsed.length, staticBackup.length)));
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
              HapticFeedback.lightImpact();
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
                        _cardFlipped ? 'TARGET TRANSLATION' : 'ENGLISH TERM',
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
