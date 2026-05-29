import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/translation_provider.dart';

class OfflineTranslationScreen extends ConsumerStatefulWidget {
  const OfflineTranslationScreen({super.key});

  @override
  ConsumerState<OfflineTranslationScreen> createState() => _OfflineTranslationScreenState();
}

class _OfflineTranslationScreenState extends ConsumerState<OfflineTranslationScreen> {
  final TextEditingController _textController = TextEditingController();
  String _debouncedQuery = '';
  Timer? _debounceTimer;
  bool _isEnglishToSpanish = true;

  final List<String> _suggestedPhrases = [
    'Hello, my friend!',
    'Where is the train station?',
    'How much does this cost?',
    'I need help, please.',
    'Thank you very much!',
    'Where is the restroom?'
  ];

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _textController.dispose();
    super.dispose();
  }

  void _onInputChanged(String text) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() {
          _debouncedQuery = text.trim();
        });
      }
    });
  }

  void _swapLanguages() {
    setState(() {
      _isEnglishToSpanish = !_isEnglishToSpanish;
      // Re-trigger translation if there is a query
      if (_textController.text.isNotEmpty) {
        _debouncedQuery = _textController.text.trim();
      }
    });
  }

  void _useSuggestion(String phrase) {
    _textController.text = phrase;
    setState(() {
      _debouncedQuery = phrase;
    });
  }

  void _clearInput() {
    _textController.clear();
    setState(() {
      _debouncedQuery = '';
    });
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle_outline_rounded, color: Color(0xFF00E676)),
            SizedBox(width: 12),
            Text('Translation copied to clipboard!'),
          ],
        ),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fromLang = _isEnglishToSpanish ? 'en' : 'es';
    final toLang = _isEnglishToSpanish ? 'es' : 'en';

    // Query translation provider reactively if query is not empty
    final translationAsync = _debouncedQuery.isNotEmpty
        ? ref.watch(translationSearchProvider((text: _debouncedQuery, from: fromLang, to: toLang)))
        : null;

    return Scaffold(
      backgroundColor: const Color(0xFF0F2027),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Phrase Translator',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16, top: 12, bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF00E676).withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF00E676).withOpacity(0.3)),
            ),
            child: const Row(
              children: [
                Icon(Icons.wifi_off_rounded, color: Color(0xFF00E676), size: 14),
                SizedBox(width: 6),
                Text(
                  'Hybrid Mode',
                  style: TextStyle(color: Color(0xFF00E676), fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Language Selection Selector Header Row
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withOpacity(0.08)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _isEnglishToSpanish ? '🇬🇧 English' : '🇪🇸 Spanish',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      IconButton(
                        icon: const Icon(Icons.swap_horiz_rounded, color: Color(0xFF00E676), size: 28),
                        onPressed: _swapLanguages,
                      ),
                      Text(
                        _isEnglishToSpanish ? '🇪🇸 Spanish' : '🇬🇧 English',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Phrase Input Box Card
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.03),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withOpacity(0.06)),
                  ),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: TextField(
                          controller: _textController,
                          onChanged: _onInputChanged,
                          maxLines: 4,
                          maxLength: 250,
                          style: const TextStyle(color: Colors.white, fontSize: 16),
                          decoration: InputDecoration(
                            hintText: 'Type phrase to translate...',
                            hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                            border: InputBorder.none,
                            counterStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                          ),
                        ),
                      ),
                      if (_textController.text.isNotEmpty)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.clear_rounded, color: Colors.white54, size: 20),
                              onPressed: _clearInput,
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Translation Result Card
                if (_debouncedQuery.isEmpty)
                  Container(
                    height: 180,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.02),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withOpacity(0.04)),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.g_translate_rounded, color: Colors.white.withOpacity(0.15), size: 48),
                          const SizedBox(height: 12),
                          Text(
                            'Your translation will appear here',
                            style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  translationAsync!.when(
                    data: (translation) => Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF162A31), Color(0xFF0D1E24)],
                        ),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFF00E676).withOpacity(0.2)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _isEnglishToSpanish ? 'SPANISH TRANSLATION' : 'ENGLISH TRANSLATION',
                                style: const TextStyle(
                                  color: Color(0xFF00E676),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                  letterSpacing: 1.5,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.copy_rounded, color: Colors.white54, size: 20),
                                onPressed: () => _copyToClipboard(translation),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            translation,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    loading: () => Container(
                      height: 140,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.03),
                        borderRadius: BorderRadius.circular(20),
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
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.redAccent.withOpacity(0.2)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 28),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Text(
                              'Translation unavailable. Check connection.',
                              style: TextStyle(color: Colors.white.withOpacity(0.8)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 36),

                // Common/Suggested Tappable Phrase Recommendation Chips
                const Text(
                  'Common Phrases',
                  style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: _suggestedPhrases
                      .map(
                        (phrase) => InkWell(
                          onTap: () => _useSuggestion(phrase),
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.06),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.white.withOpacity(0.1)),
                            ),
                            child: Text(
                              phrase,
                              style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
