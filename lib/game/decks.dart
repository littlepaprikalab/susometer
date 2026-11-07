import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';

import 'models.dart';

/// Where a warm-up sits in calibration (SPEC.md §11, decision 74). Every
/// player gets them in this order, so every baseline has the same shape.
enum WarmupSlot {
  /// Plain recall of something recent: easy to start talking.
  recall,

  /// A known-true answer in the real questions' format ("Have you ever…?
  /// Tell me about it."), with nothing at stake.
  compare,

  /// A light either/or with a reason: the kind of answer that smiles.
  light,
}

/// One question card from a deck.
class DeckQuestion {
  const DeckQuestion(this.text, {this.heat = 2, this.room = false, this.slot});

  final String text;

  /// Main decks: 1 (a warm opener) to 3 (the turn's finale).
  final int heat;

  /// Main decks: about "someone in this room", so it's only dealt when
  /// other contestants are playing.
  final bool room;

  /// Warm-ups: the calibration slot it fills. Null fits any slot.
  final WarmupSlot? slot;
}

/// Question decks from `assets/decks/*.json` (SPEC.md §11).
///
/// Each entry is a plain string, or an object:
/// `{"q": "...", "heat": 1-3, "room": true}` in the main decks and
/// `{"q": "...", "slot": "recall" | "compare" | "light"}` in the warm-ups.
/// A plain string is heat 2, not a room question, and fits any slot.
class DeckLibrary {
  const DeckLibrary({
    required this.warmup,
    required this.mild,
    required this.spicy,
  });

  final List<DeckQuestion> warmup;
  final List<DeckQuestion> mild;
  final List<DeckQuestion> spicy;

  List<DeckQuestion> main(DeckKind kind) =>
      kind == DeckKind.mild ? mild : spicy;

  static Future<DeckLibrary> load(AssetBundle bundle) async {
    Future<List<DeckQuestion>> read(String name) async {
      final raw = await bundle.loadString('assets/decks/$name.json');
      return parse(raw);
    }

    return DeckLibrary(
      warmup: await read('warmup'),
      mild: await read('mild'),
      spicy: await read('spicy'),
    );
  }

  static List<DeckQuestion> parse(String raw) {
    final json = jsonDecode(raw) as Map<String, Object?>;
    final out = <DeckQuestion>[];
    for (final q in json['questions'] as List<Object?>) {
      if (q is String) {
        if (q.trim().isNotEmpty) out.add(DeckQuestion(q.trim()));
        continue;
      }
      if (q is! Map<String, Object?>) continue;
      final text = q['q'];
      if (text is! String || text.trim().isEmpty) continue;
      final heat = q['heat'];
      out.add(
        DeckQuestion(
          text.trim(),
          heat: heat is num ? heat.round().clamp(1, 3) : 2,
          room: q['room'] == true,
          slot: WarmupSlot.values.asNameMap()[q['slot']],
        ),
      );
    }
    return out;
  }

  /// Small built-in fallback so a game can always start: two cards for
  /// every slot and heat, so "Different question" always changes it.
  static const fallback = DeckLibrary(
    warmup: [
      DeckQuestion(
        'Tell me what you had for breakfast today.',
        slot: WarmupSlot.recall,
      ),
      DeckQuestion('Walk me through your day so far.', slot: WarmupSlot.recall),
      DeckQuestion(
        'Have you ever been caught in the rain? Tell me what happened.',
        slot: WarmupSlot.compare,
      ),
      DeckQuestion(
        'Have you ever watched a sunset? Describe a good one.',
        slot: WarmupSlot.compare,
      ),
      DeckQuestion('Cats or dogs? Tell me why.', slot: WarmupSlot.light),
      DeckQuestion('Describe your perfect pizza.', slot: WarmupSlot.light),
    ],
    mild: [
      DeckQuestion('Have you ever re-gifted a present?', heat: 1),
      DeckQuestion('Did you make your bed this morning?', heat: 1),
      DeckQuestion('Be honest: do you floss every day?', heat: 2),
      DeckQuestion("What's a gift you pretended to like?", heat: 2),
      DeckQuestion('Right now, is there a message you\'re ignoring?', heat: 3),
      DeckQuestion(
        'Have you ever eaten the last cookie and denied it?',
        heat: 3,
      ),
    ],
    spicy: [
      DeckQuestion(
        'Have you ever pretended not to see someone you knew?',
        heat: 1,
      ),
      DeckQuestion(
        'Have you ever claimed a joke you heard as your own?',
        heat: 1,
      ),
      DeckQuestion('Have you ever faked being sick to skip a party?', heat: 2),
      DeckQuestion(
        'Have you ever left a party without saying goodbye?',
        heat: 2,
      ),
      DeckQuestion(
        "Have you ever read someone's texts without asking?",
        heat: 3,
      ),
      DeckQuestion(
        'Have you ever told someone their cooking was great when it wasn\'t?',
        heat: 3,
      ),
    ],
  );
}

/// The heat of question [index] (from 0) in a turn of [count]: the first
/// third is 1, the middle third 2, the last third 3, and the last question
/// is always 3. The same for every player, so their turns compare fairly
/// and each one ends on its hottest question (SPEC.md §11).
int heatFor(int index, int count) {
  if (index >= count - 1) return 3;
  return 1 + (3 * index) ~/ count;
}

/// Deals a game's main questions along the heat curve, leaving out the
/// "someone in this room" questions when nobody else is playing.
class QuestionDealer {
  QuestionDealer(
    List<DeckQuestion> deck, {
    required bool othersPresent,
    Random? random,
  }) : _piles = PileDealer({
         for (final heat in const [1, 2, 3])
           heat: [
             for (final q in deck)
               if (q.heat == heat && (othersPresent || !q.room)) q.text,
           ],
       }, random: random);

  final PileDealer<int> _piles;

  /// The question for [index] of a turn of [count]. An empty heat pile
  /// falls back to the nearest one, cooler first.
  String next(int index, int count) =>
      _piles.next(switch (heatFor(index, count)) {
        1 => const [1, 2, 3],
        2 => const [2, 1, 3],
        _ => const [3, 2, 1],
      });
}

/// Deals warm-ups slot by slot: recall, compare, light, then around again.
class WarmupDealer {
  WarmupDealer(List<DeckQuestion> deck, {Random? random})
    : _piles = PileDealer({
        for (final slot in <WarmupSlot?>[...WarmupSlot.values, null])
          slot: [
            for (final q in deck)
              if (q.slot == slot) q.text,
          ],
      }, random: random);

  final PileDealer<WarmupSlot?> _piles;

  /// The warm-up for place [n] (from 0) in a calibration. Skipped warm-ups
  /// shouldn't count, so a skip is replaced from the same slot.
  String next(int n) {
    final slot = WarmupSlot.values[n % WarmupSlot.values.length];
    return _piles.next([slot, null]);
  }
}

/// Deals from several piles. It asks the piles in the order given, then any
/// others, so an empty pile never stops the game. It never deals the same
/// text twice in a row: a one-card pile would otherwise repeat itself on
/// "Different question".
class PileDealer<K> {
  PileDealer(Map<K, List<String>> piles, {Random? random})
    : _piles = {
        for (final e in piles.entries)
          if (e.value.isNotEmpty) e.key: DeckDealer(e.value, random: random),
      };

  final Map<K, DeckDealer> _piles;
  String? _last;

  String next(List<K> order) {
    final keys = [
      ...order.where(_piles.containsKey),
      ..._piles.keys.where((k) => !order.contains(k)),
    ];
    String? fallback;
    for (final k in keys) {
      final q = _piles[k]!.next();
      if (q != _last) return _last = q;
      fallback ??= q;
    }
    return _last = fallback ?? '';
  }
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
