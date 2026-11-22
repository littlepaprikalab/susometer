// What the demo film looks like: the real app in a phone on the left, the
// "room" with stand-in people on the right (the slot real clips go in), and
// what's being said underneath.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:susometer/main.dart';
import 'package:susometer/presage/camera_preview.dart';
import 'package:susometer/theme/game_widgets.dart';
import 'package:susometer/theme/tokens.dart';

import 'film.dart';

const _stageInk = Color(0xFF1C0E07);
const _wall = Color(0xFF1B4A51);
const _muted = Color(0xFFCDB894);

TextStyle _body(double size, {Color color = SusColors.cream, FontWeight? w}) =>
    TextStyle(
      fontFamily: SusFonts.body,
      fontSize: size,
      fontWeight: w ?? FontWeight.w600,
      color: color,
      height: 1.25,
      decoration: TextDecoration.none,
    );

TextStyle _display(double size, {Color color = SusColors.cream}) => TextStyle(
  fontFamily: SusFonts.display,
  fontSize: size,
  color: color,
  height: 1.05,
  decoration: TextDecoration.none,
);

class Stage extends StatelessWidget {
  const Stage(this.film, {super.key});

  final Film film;

  static const phoneSize = Size(390, 844);
  static const phoneScale = 1.19;
  static const bezel = 14.0;
  static const phone = Rect.fromLTWH(
    70,
    24,
    390 * phoneScale + 2 * bezel,
    844 * phoneScale + 2 * bezel,
  );

  /// The room picture: 16:9, where a real clip goes.
  static const room = Rect.fromLTWH(640, 128, 1216, 684);

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: _stageInk,
        child: Stack(
          children: [
            Positioned.fromRect(rect: phone, child: _Phone(film)),
            Positioned.fill(
              child: ListenableBuilder(
                listenable: film.tick,
                builder: (context, _) => _Overlay(film),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Phone extends StatelessWidget {
  const _Phone(this.film);

  final Film film;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF0D0705),
        borderRadius: BorderRadius.circular(58),
        border: Border.all(color: const Color(0xFF5B4636), width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Stage.bezel),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(46),
          child: FittedBox(
            child: SizedBox.fromSize(
              size: Stage.phoneSize,
              child: MediaQuery(
                data: const MediaQueryData(
                  size: Stage.phoneSize,
                  devicePixelRatio: 3,
                  padding: EdgeInsets.only(top: 47, bottom: 34),
                  viewPadding: EdgeInsets.only(top: 47, bottom: 34),
                ),
                child: Stack(
                  children: [
                    SusApp(services: film.services),
                    // The island and the home bar, so it reads as a phone.
                    const Positioned(
                      top: 11,
                      left: 0,
                      right: 0,
                      child: Center(child: _Pill(118, 33, Color(0xFF0D0705))),
                    ),
                    const Positioned(
                      bottom: 9,
                      left: 0,
                      right: 0,
                      child: Center(child: _Pill(134, 5, SusColors.ink)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.w, this.h, this.color);

  final double w;
  final double h;
  final Color color;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(h / 2),
      ),
    ),
  );
}

/// Everything that moves with the film's clock.
class _Overlay extends StatelessWidget {
  const _Overlay(this.film);

  final Film film;

  @override
  Widget build(BuildContext context) {
    final now = film.now;
    final card = film.card;
    final jump = film.jump;
    return Stack(
      children: [
        // Header: which game, which step.
        Positioned(
          left: Stage.room.left,
          top: 34,
          width: Stage.room.width,
          height: 80,
          child: Row(
            children: [
              if (film.chapter.isNotEmpty)
                Container(
                  padding: const EdgeInsets.fromLTRB(18, 10, 18, 8),
                  decoration: BoxDecoration(
                    color: SusColors.tomato,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: SusColors.cream, width: 3),
                  ),
                  child: Text(film.chapter, style: _display(26)),
                ),
              const SizedBox(width: 20),
              Expanded(
                child: Text(
                  film.step,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _display(32, color: SusColors.bulb),
                ),
              ),
              if (jump != null && now < jump.$2)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: SusColors.cream,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.fast_forward_rounded,
                        color: SusColors.ink,
                        size: 26,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        jump.$1,
                        style: _body(
                          20,
                          color: SusColors.ink,
                          w: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        Positioned.fromRect(rect: Stage.room, child: Room(film)),
        Positioned(
          left: Stage.room.left,
          top: Stage.room.bottom + 22,
          width: Stage.room.width,
          height: 170,
          child: _Caption(film),
        ),
        Positioned(
          left: Stage.room.left,
          bottom: 22,
          width: Stage.room.width,
          child: Text(
            'Animatic · stand-in people, simulated signals · '
            'the phone shows the real app screens',
            style: _body(17, color: _muted.withValues(alpha: 0.75)),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(painter: _TapPainter(film.taps, now)),
          ),
        ),
        if (card != null) Positioned.fill(child: _Card(card)),
      ],
    );
  }
}

/// What's being said right now (or what's going on, when nobody talks).
class _Caption extends StatelessWidget {
  const _Caption(this.film);

  final Film film;

  @override
  Widget build(BuildContext context) {
    final now = film.now;
    Line? line = film.hostLine;
    for (final a in film.cast) {
      final l = a.line;
      if (l != null && now < l.startMs + l.durMs + 500) {
        if (line == null || l.startMs > line.startMs) line = l;
      }
    }
    if (line == null) {
      return Text(
        film.note,
        maxLines: 3,
        style: _body(27, color: _muted, w: FontWeight.w500),
      );
    }
    final host = line.speaker == 'Host';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: host ? SusColors.teal : SusColors.cream,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (host)
                const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: Icon(
                    Icons.campaign_rounded,
                    color: SusColors.cream,
                    size: 26,
                  ),
                ),
              Text(
                host ? 'HOST' : line.speaker.toUpperCase(),
                style: _body(
                  22,
                  w: FontWeight.w700,
                  color: host ? SusColors.cream : SusColors.ink,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Text(
            '“${line.text}”',
            maxLines: 3,
            style: _body(34, w: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card(this.card);

  final TitleCard card;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: SusColors.mustard,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (card.kicker != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 26),
                child: Text(
                  card.kicker!,
                  style: _display(40, color: SusColors.ink),
                ),
              ),
            Container(
              padding: const EdgeInsets.fromLTRB(70, 26, 70, 26),
              decoration: BoxDecoration(
                color: SusColors.tomato,
                borderRadius: BorderRadius.circular(44),
                border: Border.all(color: SusColors.ink, width: 6),
                boxShadow: const [
                  BoxShadow(color: SusColors.ink, offset: Offset(0, 12)),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _Bulbs(),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    child: Text(card.title, style: _display(120)),
                  ),
                  const _Bulbs(),
                ],
              ),
            ),
            const SizedBox(height: 52),
            for (final l in card.lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  l,
                  textAlign: TextAlign.center,
                  style: _body(40, color: SusColors.ink, w: FontWeight.w600),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Bulbs extends StatelessWidget {
  const _Bulbs();

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var i = 0; i < 14; i++)
        Container(
          width: 20,
          height: 20,
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: SusColors.bulb,
            shape: BoxShape.circle,
            border: Border.all(color: SusColors.ink, width: 3),
          ),
        ),
    ],
  );
}

class _TapPainter extends CustomPainter {
  _TapPainter(this.taps, this.now);

  final List<(Offset, int)> taps;
  final int now;

  @override
  void paint(Canvas canvas, Size size) {
    for (final (p, at) in taps) {
      final f = (now - at) / 420;
      if (f < 0 || f > 1) continue;
      final fade = 1 - f;
      canvas.drawCircle(
        p,
        16 + 34 * f,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..color = Colors.white.withValues(alpha: 0.9 * fade),
      );
      canvas.drawCircle(
        p,
        15,
        Paint()..color = Colors.white.withValues(alpha: 0.55 * fade),
      );
      canvas.drawCircle(
        p,
        15,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = SusColors.ink.withValues(alpha: 0.8 * fade),
      );
    }
  }

  @override
  bool shouldRepaint(_TapPainter old) => true;
}

// -----------------------------------------------------------------------------
// The room

/// The stand-ins around the phone. The hot seat sits on the left, facing the
/// phone on the table; everyone else on the right.
class Room extends StatelessWidget {
  const Room(this.film, {super.key});

  final Film film;

  static const tableY = 520.0;

  @override
  Widget build(BuildContext context) {
    final now = film.now;
    final seat = film.hotSeat ?? (film.cast.isEmpty ? null : film.cast.first);
    final others = [
      for (final a in film.cast)
        if (!identical(a, seat)) a,
    ];
    final solo = others.isEmpty;
    // Two players face each other across the phone; more sit in a row.
    final pair = others.length == 1;
    final seatX = solo ? 400.0 : (pair ? 300.0 : 215.0);
    final seatScale = solo ? 1.2 : (pair ? 1.0 : 0.95);
    final phoneX = solo ? 830.0 : (pair ? 545.0 : 432.0);
    final guestScale = pair ? 0.95 : (others.length > 3 ? 0.6 : 0.72);
    final span = others.length > 3 ? 190.0 : 215.0;
    final guestsRight = pair ? 330.0 : 150.0;
    final shot = film.shot;
    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          const Positioned.fill(child: CustomPaint(painter: _SetPainter())),
          if (seat != null) _bust(seat, seatX, seatScale, now, true),
          for (var i = 0; i < others.length; i++)
            _bust(
              others[i],
              1216 - guestsRight - span * (others.length - 1 - i),
              guestScale,
              now,
              false,
              lift: i.isOdd ? 14 : 0,
            ),
          // The table, in front of everyone.
          const Positioned(
            left: 0,
            right: 0,
            top: tableY,
            bottom: 0,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: SusColors.brown,
                border: Border(top: BorderSide(color: SusColors.ink, width: 5)),
              ),
            ),
          ),
          Positioned(
            left: phoneX - 60,
            top: tableY - (solo ? 150 : 104),
            child: CustomPaint(
              size: solo ? const Size(120, 190) : const Size(84, 134),
              painter: _PropPhonePainter(
                speaking: film.hostLine != null,
                now: now,
              ),
            ),
          ),
          if (seat != null) _tag(seat, seatX, film.hotSeat != null),
          for (var i = 0; i < others.length; i++)
            _tag(
              others[i],
              1216 - guestsRight - span * (others.length - 1 - i),
              false,
            ),
          if (seat != null) ..._bubble(seat, seatX, seatScale, now, 0),
          for (var i = 0; i < others.length; i++)
            ..._bubble(
              others[i],
              1216 - guestsRight - span * (others.length - 1 - i),
              guestScale,
              now,
              i.isOdd ? 14 : 0,
            ),
          if (shot != null)
            Positioned(
              left: 18,
              bottom: 14,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _stageInk.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'STAND-IN  ·  shot ${shot.id}  ·  ${shot.what}',
                  style: _body(17, color: SusColors.bulb, w: FontWeight.w700),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _bust(
    Actor a,
    double cx,
    double scale,
    int now,
    bool seat, {
    double lift = 0,
  }) {
    final w = 300 * scale;
    final h = 400 * scale;
    return Positioned(
      left: cx - w / 2,
      top: tableY - h + 70 * scale - lift,
      width: w,
      height: h,
      child: CustomPaint(painter: BustPainter(a, now)),
    );
  }

  Widget _tag(Actor a, double cx, bool seat) {
    return Positioned(
      left: cx - 130,
      width: 260,
      top: tableY + 26,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 7, 16, 5),
            decoration: BoxDecoration(
              color: SusColors.ink,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: SusColors.cream, width: 2.5),
            ),
            child: Text(a.name.toUpperCase(), style: _display(22)),
          ),
          if (seat)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'IN THE HOT SEAT',
                style: _body(17, color: SusColors.bulb, w: FontWeight.w700),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _bubble(Actor a, double cx, double scale, int now, double lift) {
    final line = a.line;
    if (line == null || now > line.startMs + line.durMs + 700) return const [];
    final headTop = tableY - 400 * scale + 70 * scale - lift + 40 * scale;
    final words = line.text.split(' ');
    final shown = (line.said(now) * words.length).ceil().clamp(1, words.length);
    final width = scale > 1 ? 480.0 : 400.0;
    final left = (cx - width / 2).clamp(14.0, 1216 - width - 14);
    return [
      Positioned(
        left: left,
        width: width,
        bottom: 684 - headTop + 20,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
            decoration: BoxDecoration(
              color: SusColors.cream,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: SusColors.ink, width: 4),
            ),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: words.take(shown).join(' ')),
                  if (shown < words.length)
                    TextSpan(
                      text: ' ${words.skip(shown).join(' ')}',
                      style: const TextStyle(color: Colors.transparent),
                    ),
                ],
              ),
              textAlign: TextAlign.center,
              style: _body(25, color: SusColors.ink),
            ),
          ),
        ),
      ),
      Positioned(
        left: cx - 14,
        bottom: 684 - headTop + 2,
        child: CustomPaint(size: const Size(28, 22), painter: _TailPainter()),
      ),
    ];
  }
}

class _TailPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0);
    canvas.drawPath(path, Paint()..color = SusColors.cream);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeJoin = StrokeJoin.round
        ..color = SusColors.ink,
    );
    // Hide the bubble's border where the tail joins it.
    canvas.drawRect(
      Rect.fromLTWH(3, -3, size.width - 6, 5),
      Paint()..color = SusColors.cream,
    );
  }

  @override
  bool shouldRepaint(_TailPainter old) => false;
}

/// The wall behind the stand-ins: teal, with a 70s stripe.
class _SetPainter extends CustomPainter {
  const _SetPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = _wall);
    const stripes = [SusColors.mustard, SusColors.tomato, SusColors.cream];
    for (var i = 0; i < stripes.length; i++) {
      canvas.drawRect(
        Rect.fromLTWH(0, 318 + i * 22.0, size.width, 22),
        Paint()..color = stripes[i].withValues(alpha: 0.5),
      );
    }
  }

  @override
  bool shouldRepaint(_SetPainter old) => false;
}

/// The phone on the table, seen from the room: its back, on a little stand,
/// with sound coming out while the host talks.
class _PropPhonePainter extends CustomPainter {
  _PropPhonePainter({required this.speaking, required this.now});

  final bool speaking;
  final int now;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final ink = Paint()..color = _stageInk;
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = SusColors.cream;
    // Stand.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.2, h * 0.9, w * 0.6, h * 0.1),
        const Radius.circular(6),
      ),
      ink,
    );
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.25, h * 0.12, w * 0.5, h * 0.8),
      Radius.circular(w * 0.1),
    );
    canvas.drawRRect(body, ink);
    canvas.drawRRect(body, edge);
    canvas.drawCircle(
      Offset(w * 0.38, h * 0.22),
      w * 0.05,
      Paint()..color = SusColors.cream,
    );
    if (speaking) {
      for (var i = 0; i < 3; i++) {
        final f = ((now / 700) + i / 3) % 1;
        canvas.drawArc(
          Rect.fromCircle(
            center: Offset(w * 0.5, h * 0.12),
            radius: w * (0.25 + 0.5 * f),
          ),
          -math.pi * 0.8,
          math.pi * 0.6,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4
            ..strokeCap = StrokeCap.round
            ..color = SusColors.bulb.withValues(alpha: 1 - f),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_PropPhonePainter old) => true;
}

/// A stand-in: head and shoulders, drawn in a 300×400 box. Blinks, talks,
/// and wears its [Mood].
class BustPainter extends CustomPainter {
  BustPainter(this.a, this.now, {this.close = false});

  final Actor a;
  final int now;

  /// The camera's view: no paddle, no bob.
  final bool close;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 300;
    canvas.save();
    canvas.scale(s);
    final phase = a.name.codeUnits.fold<int>(0, (x, c) => x + c * 131);
    final laugh = a.mood == Mood.laugh;
    final bob = close
        ? 0.0
        : (laugh ? 7 * math.sin(now / 95 + phase).abs() : 0) +
              2.5 * math.sin(now / 900 + phase) +
              (a.talking ? 2 * math.sin(now / 170 + phase) : 0);
    canvas.translate(0, -bob);

    final ink = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..color = SusColors.ink;
    final skin = Paint()..color = a.skin;
    final hair = Paint()..color = a.hair;
    const head = Rect.fromLTRB(80, 50, 220, 210);

    // Paddle (behind the shoulder).
    final sus = a.paddleSus;
    if (sus != null && !close) {
      canvas.drawLine(
        const Offset(258, 330),
        const Offset(276, 130),
        Paint()
          ..strokeWidth = 12
          ..strokeCap = StrokeCap.round
          ..color = SusColors.ink,
      );
      const c = Offset(278, 84);
      canvas.drawCircle(
        c,
        52,
        Paint()..color = sus ? SusColors.tomatoDeep : SusColors.teal,
      );
      canvas.drawCircle(c, 52, ink);
      final tp = TextPainter(
        text: TextSpan(
          text: sus ? 'SUS' : 'LEGIT',
          style: _display(sus ? 31 : 23),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2 - 2));
    }

    // Long hair falls behind the head.
    if (a.hairStyle == 1) {
      final back = RRect.fromLTRBR(66, 62, 234, 262, const Radius.circular(60));
      canvas.drawRRect(back, hair);
      canvas.drawRRect(back, ink);
    }
    // Shoulders and neck.
    final body = RRect.fromLTRBAndCorners(
      18,
      236,
      282,
      420,
      topLeft: const Radius.circular(78),
      topRight: const Radius.circular(78),
    );
    canvas.drawRRect(body, Paint()..color = a.shirt);
    canvas.drawRRect(body, ink);
    final neck = RRect.fromLTRBR(124, 190, 176, 250, const Radius.circular(18));
    canvas.drawRRect(neck, skin);
    canvas.drawRRect(neck, ink);
    canvas.drawRect(const Rect.fromLTRB(127, 190, 173, 215), skin);

    // Head.
    canvas.drawOval(head, skin);
    canvas.drawOval(head, ink);

    // Hair on top.
    final cap = Path.combine(
      PathOperation.intersect,
      Path()..addOval(head.inflate(6)),
      Path()
        ..moveTo(0, 0)
        ..lineTo(300, 0)
        ..lineTo(300, 96)
        ..quadraticBezierTo(190, 70, 150, 100)
        ..quadraticBezierTo(110, 78, 0, 100)
        ..close(),
    );
    if (a.hairStyle == 2) {
      canvas.drawCircle(const Offset(150, 40), 28, hair);
      canvas.drawCircle(const Offset(150, 40), 28, ink);
    }
    if (a.hairStyle == 3) {
      for (var i = 0; i <= 8; i++) {
        final ang = math.pi + math.pi * i / 8;
        final c = Offset(150 + 72 * math.cos(ang), 118 + 76 * math.sin(ang));
        canvas.drawCircle(c, 25, hair);
        canvas.drawCircle(c, 25, ink);
      }
      for (var i = 0; i <= 8; i++) {
        final ang = math.pi + math.pi * i / 8;
        canvas.drawCircle(
          Offset(150 + 70 * math.cos(ang), 118 + 74 * math.sin(ang)),
          22,
          hair,
        );
      }
    }
    canvas.drawPath(cap, hair);
    canvas.drawPath(cap, ink);

    // Face.
    final blink =
        now < a.blinkUntil || (!close && (now + phase * 37) % 3900 < 140);
    final surprised = a.mood == Mood.surprised;
    final nervous = a.mood == Mood.nervous;
    final happy = a.mood == Mood.happy || laugh;
    final fill = Paint()..color = SusColors.ink;
    for (final dx in const [-27.0, 27.0]) {
      final e = Offset(150 + dx, 132);
      if (blink) {
        canvas.drawLine(e - const Offset(9, 0), e + const Offset(9, 0), ink);
      } else if (laugh) {
        canvas.drawArc(
          Rect.fromCenter(
            center: e + const Offset(0, 4),
            width: 22,
            height: 18,
          ),
          math.pi,
          math.pi,
          false,
          ink,
        );
      } else {
        if (surprised) {
          canvas.drawCircle(e, 13, Paint()..color = Colors.white);
        }
        canvas.drawCircle(e, surprised ? 7 : 8, fill);
      }
      // Brows.
      final up = surprised ? 12.0 : 0.0;
      final tilt = nervous ? -8.0 * dx.sign : (happy ? -2.0 * dx.sign : 0.0);
      canvas.drawLine(
        Offset(150 + dx - 13, 110 - up + tilt),
        Offset(150 + dx + 13, 110 - up - tilt),
        ink,
      );
    }
    if (nervous || laugh) {
      final blush = Paint()..color = SusColors.tomato.withValues(alpha: 0.28);
      canvas.drawCircle(const Offset(108, 160), 13, blush);
      canvas.drawCircle(const Offset(192, 160), 13, blush);
    }
    if (nervous) {
      final drop = Path()
        ..moveTo(226, 82)
        ..quadraticBezierTo(240, 104, 226, 108)
        ..quadraticBezierTo(212, 104, 226, 82);
      canvas.drawPath(drop, Paint()..color = const Color(0xFF9FD8E6));
      canvas.drawPath(drop, ink..strokeWidth = 3);
      ink.strokeWidth = 5;
    }
    // Mouth.
    const m = Offset(150, 176);
    if (a.talking) {
      final open = 0.3 + 0.7 * math.sin(now / 82 + phase).abs();
      canvas.drawOval(
        Rect.fromCenter(center: m, width: 30, height: 8 + 20 * open),
        fill,
      );
    } else if (laugh) {
      final mouth = Path()
        ..moveTo(126, 168)
        ..lineTo(174, 168)
        ..quadraticBezierTo(150, 204, 126, 168);
      canvas.drawPath(mouth, fill);
      canvas.drawPath(mouth, ink);
    } else if (surprised) {
      canvas.drawOval(Rect.fromCenter(center: m, width: 18, height: 22), fill);
    } else if (nervous) {
      final mouth = Path()
        ..moveTo(128, 178)
        ..quadraticBezierTo(139, 170, 150, 178)
        ..quadraticBezierTo(161, 186, 172, 178);
      canvas.drawPath(mouth, ink);
    } else {
      final wide = happy ? 26.0 : 18.0;
      final mouth = Path()
        ..moveTo(150 - wide, 172)
        ..quadraticBezierTo(150, 172 + (happy ? 24 : 12), 150 + wide, 172);
      canvas.drawPath(mouth, ink);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(BustPainter old) => true;
}

/// What the app's camera window shows in the film: the stand-in in the hot
/// seat, face in the oval.
class CameraStandIn extends StatelessWidget {
  const CameraStandIn(this.film, {super.key});

  final Film film;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: film.tick,
      builder: (context, _) {
        final a = film.hotSeat;
        return ColoredBox(
          color: const Color(0xFF3B6168),
          child: a == null
              ? null
              : LayoutBuilder(
                  builder: (context, box) {
                    final oval = faceOvalRect(
                      box.biggest,
                      cameraGuideClear(context),
                    );
                    // The head is 140×160 of the bust's 300×400, centred at
                    // (150, 130): it sits just inside the oval.
                    final scale = oval.width * 0.94 / 140;
                    return Stack(
                      clipBehavior: Clip.hardEdge,
                      children: [
                        Positioned(
                          left: oval.center.dx - 150 * scale,
                          top: oval.center.dy - 130 * scale,
                          width: 300 * scale,
                          height: 400 * scale,
                          child: CustomPaint(
                            painter: BustPainter(a, film.now, close: true),
                          ),
                        ),
                      ],
                    );
                  },
                ),
        );
      },
    );
  }
}
