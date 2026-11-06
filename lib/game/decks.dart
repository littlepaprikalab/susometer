import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';

import 'models.dart';

/// Question decks from `assets/decks/*.json` (SPEC.md §11).
class DeckLibrary {
  const DeckLibrary({
    required this.warmup,
    required this.mild,
    required this.spicy,
  });

  final List<String> warmup;
  final List<String> mild;
  final List<String> spicy;

  List<String> main(DeckKind kind) => kind == DeckKind.mild ? mild : spicy;

  static Future<DeckLibrary> load(AssetBundle bundle) async {
    Future<List<String>> read(String name) async {
      final raw = await bundle.loadString('assets/decks/$name.json');
      return parse(raw);
    }

    return DeckLibrary(
      warmup: await read('warmup'),
      mild: await read('mild'),
      spicy: await read('spicy'),
    );
  }

  static List<String> parse(String raw) {
    final json = jsonDecode(raw) as Map<String, Object?>;
    return [
      for (final q in json['questions'] as List<Object?>)
        if (q is String && q.trim().isNotEmpty) q.trim(),
    ];
  }

  /// Small built-in fallback so a game can always start.
  static const fallback = DeckLibrary(
    warmup: [
      'Tell me what you had for breakfast today.',
      'Describe the weather outside right now.',
      'Describe something blue you can see from here.',
    ],
    mild: [
      'Have you ever re-gifted a present?',
      'Do you floss every day?',
      'Have you ever pretended to like a gift?',
    ],
    spicy: [
      "Have you ever read someone's texts?",
      'Do you actually like your boss?',
      'Have you ever faked being sick to skip a party?',
    ],
  );
}

/// Deals questions in a shuffled order with no repeats within a game. When a
/// deck runs out it reshuffles, avoiding an immediate repeat.
class DeckDealer {
  DeckDealer(List<String> items, {Random? random})
    : _items = List.unmodifiable(items),
      _random = random ?? Random();

  final List<String> _items;
  final Random _random;
  final List<String> _queue = [];
  String? _last;

  int get size => _items.length;

  String next() {
    if (_items.isEmpty) return '';
    if (_queue.isEmpty) {
      _queue.addAll(_items);
      _queue.shuffle(_random);
      if (_queue.length > 1 && _queue.first == _last) {
        _queue.add(_queue.removeAt(0));
      }
    }
    final item = _queue.removeAt(0);
    _last = item;
    return item;
  }
}
