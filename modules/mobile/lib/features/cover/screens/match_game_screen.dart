import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/mock_dictionary.dart';
import '../providers/target_language_provider.dart';

class GameCard {
  final String id;
  final String text;
  final bool isEnglish;
  bool isMatched;

  GameCard({required this.id, required this.text, required this.isEnglish, this.isMatched = false});
}

class MatchGameScreen extends ConsumerStatefulWidget {
  final ValueChanged<int> onCompleted;
  const MatchGameScreen({super.key, required this.onCompleted});

  @override
  ConsumerState<MatchGameScreen> createState() => _MatchGameScreenState();
}

class _MatchGameScreenState extends ConsumerState<MatchGameScreen> {
  final List<GameCard> _cards = [];
  GameCard? _selectedCard;
  List<GameCard> _incorrectCards = [];
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initGame();
    });
  }

  void _initGame() {
    final langCode = ref.read(targetLanguageProvider);
    setState(() {
      _cards.clear();
      final randomEntries = getRandomWords(6);
      for (final entry in randomEntries) {
        final enWord = entry.key;
        final targetWord = entry.value[langCode] ?? entry.value['es']!;
        _cards.add(GameCard(id: enWord, text: enWord, isEnglish: true));
        _cards.add(GameCard(id: enWord, text: targetWord, isEnglish: false));
      }
      _cards.shuffle();
    });
  }

  void _onCardTap(GameCard card) async {
    if (_isProcessing || card.isMatched || card == _selectedCard) return;

    setState(() {
      if (_selectedCard == null) {
        _selectedCard = card;
      } else {
        _isProcessing = true;
        if (_selectedCard!.id == card.id && _selectedCard!.isEnglish != card.isEnglish) {
          // Match
          HapticFeedback.mediumImpact();
          _selectedCard!.isMatched = true;
          card.isMatched = true;
          _selectedCard = null;
          _isProcessing = false;
          _checkWin();
        } else {
          // Mismatch
          HapticFeedback.vibrate();
          _incorrectCards = [_selectedCard!, card];
          _selectedCard = null;
          Future.delayed(const Duration(milliseconds: 600), () {
            if (mounted) {
              setState(() {
                _incorrectCards.clear();
                _isProcessing = false;
              });
            }
          });
        }
      }
    });
  }

  void _checkWin() {
    if (_cards.every((c) => c.isMatched)) {
      widget.onCompleted(50); // reward 50 XP
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF1F3A45),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('🎉 You won!', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          content: const Text('You matched all pairs.\n\nReward: +50 XP!', style: TextStyle(color: Colors.white70)),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // pop dialog
                Navigator.of(context).pop(); // pop modal
              },
              child: const Text('Awesome', style: TextStyle(color: Color(0xFF00E676), fontWeight: FontWeight.bold)),
            )
          ],
        )
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_cards.isEmpty) {
      return const Scaffold(
        backgroundColor: Color(0xFF0F2027),
        body: Center(child: CircularProgressIndicator(color: Color(0xFF00E676))),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0F2027),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Match the Pairs', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              const Text(
                'Tap matching words to clear the board!',
                style: TextStyle(color: Colors.white70, fontSize: 16),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 0.8,
                  ),
                  itemCount: _cards.length,
                  itemBuilder: (context, index) {
                    final card = _cards[index];
                    final isSelected = _selectedCard == card;
                    final isIncorrect = _incorrectCards.contains(card);

                    Color bgColor = Colors.white.withOpacity(0.05);
                    Color borderColor = Colors.white.withOpacity(0.1);

                    if (card.isMatched) {
                      bgColor = const Color(0xFF00E676).withOpacity(0.1);
                      borderColor = const Color(0xFF00E676).withOpacity(0.3);
                    } else if (isIncorrect) {
                      bgColor = Colors.redAccent.withOpacity(0.2);
                      borderColor = Colors.redAccent;
                    } else if (isSelected) {
                      bgColor = const Color(0xFF00E676).withOpacity(0.1);
                      borderColor = const Color(0xFF00E676).withOpacity(0.5);
                    }

                    return GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        _onCardTap(card);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        decoration: BoxDecoration(
                          color: bgColor,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: borderColor, width: 2),
                        ),
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Text(
                              card.text,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: card.isMatched ? const Color(0xFF00E676).withOpacity(0.5) : Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
