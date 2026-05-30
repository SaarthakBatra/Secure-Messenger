import 'dart:math';

final Map<String, Map<String, String>> globalMockDictionary = {
  'apple': {'es': 'manzana', 'fr': 'pomme', 'ja': 'りんご', 'de': 'Apfel', 'it': 'mela'},
  'water': {'es': 'agua', 'fr': 'eau', 'ja': '水', 'de': 'Wasser', 'it': 'acqua'},
  'cat': {'es': 'gato', 'fr': 'chat', 'ja': '猫', 'de': 'Katze', 'it': 'gatto'},
  'dog': {'es': 'perro', 'fr': 'chien', 'ja': '犬', 'de': 'Hund', 'it': 'cane'},
  'book': {'es': 'libro', 'fr': 'livre', 'ja': '本', 'de': 'Buch', 'it': 'libro'},
  'friend': {'es': 'amigo', 'fr': 'ami', 'ja': '友達', 'de': 'Freund', 'it': 'amico'},
  'school': {'es': 'escuela', 'fr': 'école', 'ja': '学校', 'de': 'Schule', 'it': 'scuola'},
  'house': {'es': 'casa', 'fr': 'maison', 'ja': '家', 'de': 'Haus', 'it': 'casa'},
  'sun': {'es': 'sol', 'fr': 'soleil', 'ja': '太陽', 'de': 'Sonne', 'it': 'sole'},
  'moon': {'es': 'luna', 'fr': 'lune', 'ja': '月', 'de': 'Mond', 'it': 'luna'},
  'tree': {'es': 'árbol', 'fr': 'arbre', 'ja': '木', 'de': 'Baum', 'it': 'albero'},
  'car': {'es': 'coche', 'fr': 'voiture', 'ja': '車', 'de': 'Auto', 'it': 'macchina'},
  'bread': {'es': 'pan', 'fr': 'pain', 'ja': 'パン', 'de': 'Brot', 'it': 'pane'},
  'cheese': {'es': 'queso', 'fr': 'fromage', 'ja': 'チーズ', 'de': 'Käse', 'it': 'formaggio'},
  'flower': {'es': 'flor', 'fr': 'fleur', 'ja': '花', 'de': 'Blume', 'it': 'fiore'},
  'bird': {'es': 'pájaro', 'fr': 'oiseau', 'ja': '鳥', 'de': 'Vogel', 'it': 'uccello'},
  'fish': {'es': 'pez', 'fr': 'poisson', 'ja': '魚', 'de': 'Fisch', 'it': 'pesce'},
  'milk': {'es': 'leche', 'fr': 'lait', 'ja': '牛乳', 'de': 'Milch', 'it': 'latte'},
  'city': {'es': 'ciudad', 'fr': 'ville', 'ja': '都市', 'de': 'Stadt', 'it': 'città'},
  'music': {'es': 'música', 'fr': 'musique', 'ja': '音楽', 'de': 'Musik', 'it': 'musica'},
};

List<MapEntry<String, Map<String, String>>> getRandomWords(int count) {
  final entries = globalMockDictionary.entries.toList();
  entries.shuffle(Random());
  return entries.take(count).toList();
}
