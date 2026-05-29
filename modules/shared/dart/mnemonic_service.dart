// BIP-39 Mnemonic Service (Dart)
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_sodium/flutter_sodium.dart';
import 'bip39_wordlist.dart';

class MnemonicService {
  /// Generates a 12-word BIP-39 phrase using libsodium random entropy.
  /// 128-bit entropy + 4-bit SHA-256 checksum = 132 bits = 12 words.
  static String generateMnemonic() {
    // 1. Generate 16 bytes of secure random entropy via libsodium
    final Uint8List entropy = Sodium.randombytesBuf(16);

    // 2. Compute SHA-256 of entropy to get the 4-bit checksum
    final Digest digest = sha256.convert(entropy);
    final int checksumByte = digest.bytes[0];
    final int checksum4Bits = (checksumByte >> 4) & 0x0F;

    // 3. Map the 132 bits (128 bits of entropy + 4 bits of checksum)
    // into 12 indices of 11 bits each
    final List<int> wordIndices = List<int>.filled(12, 0);
    int bitBuffer = 0;
    int bitCount = 0;
    int wordIndex = 0;

    for (int i = 0; i < 16; i++) {
      bitBuffer = (bitBuffer << 8) | entropy[i];
      bitCount += 8;

      while (bitCount >= 11) {
        wordIndices[wordIndex++] = (bitBuffer >> (bitCount - 11)) & 0x7FF;
        bitCount -= 11;
      }
    }

    // Append 4-bit checksum
    bitBuffer = (bitBuffer << 4) | checksum4Bits;
    bitCount += 4;

    if (bitCount == 11 && wordIndex == 11) {
      wordIndices[wordIndex] = bitBuffer & 0x7FF;
    } else {
      throw StateError('CRYPTO_008: BIP-39 generation bit-alignment error');
    }

    // 4. Map indices to English word list
    final List<String> words = wordIndices.map((idx) => bip39Wordlist[idx]).toList();
    return words.join(' ');
  }

  /// Generates 3 unique sorted random indices from 0 to 11 for onboarding confirmation.
  static List<int> generateConfirmationIndices() {
    final List<int> indices = <int>[];
    while (indices.length < 3) {
      final Uint8List randBytes = Sodium.randombytesBuf(1);
      final int idx = randBytes[0] % 12;
      if (!indices.contains(idx)) {
        indices.add(idx);
      }
    }
    indices.sort();
    return indices;
  }
}
