import 'package:material_ui/material_ui.dart';

import '../services/friends.dart';
import '../services/reactions.dart';
import '../services/share.dart';
import '../services/storage.dart';
import 'palette.dart';
import 'sheets.dart';
import 'squish.dart';

/// Asks once for the name friends will see. Returns the name, or '' if the
/// player skipped (we don't ask again).
Future<String> ensureName(BuildContext context, Storage storage) async {
  if (storage.myName.isNotEmpty || storage.askedName) return storage.myName;
  final name = await showDialog<String>(context: context, builder: (_) => const _NameDialog());
  await storage.setAskedName();
  final clean = cleanName(name ?? '');
  if (clean.isNotEmpty) await storage.setMyName(clean);
  return clean;
}

class _NameDialog extends StatefulWidget {
  const _NameDialog();
  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Palette.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      title: Text('Who\'s sorting?', textAlign: TextAlign.center, style: Palette.display(size: 24)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Friends who open your link will see this name on their board.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Palette.inkSoft),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _c,
            autofocus: true,
            maxLength: 16,
            textCapitalization: TextCapitalization.words,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Palette.ink),
            decoration: InputDecoration(
              hintText: 'Your first name',
              counterText: '',
              filled: true,
              fillColor: Palette.background,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
            ),
            onSubmitted: (v) => Navigator.pop(context, v),
          ),
        ],
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, ''),
          child: Text(
            'Skip',
            style: TextStyle(fontWeight: FontWeight.w800, color: Palette.inkSoft),
          ),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Palette.ink,
            foregroundColor: Palette.onInk,
            shape: const StadiumBorder(),
          ),
          onPressed: () => Navigator.pop(context, _c.text),
          child: const Text('Save', style: TextStyle(fontWeight: FontWeight.w900)),
        ),
      ],
    );
  }
}

Color avatarColor(String name) => Palette.balls[name.toLowerCase().hashCode.abs() % 5];

class Avatar extends StatelessWidget {
  final String name;
  final double size;
  const Avatar(this.name, {super.key, this.size = 36});

  @override
  Widget build(BuildContext context) {
    final c = avatarColor(name);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color.lerp(c, Colors.white, 0.25)!, c],
        ),
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [BoxShadow(color: Color(0x22241A10), blurRadius: 4, offset: Offset(0, 2))],
      ),
      child: Text(
        name.isEmpty ? '?' : name.characters.first.toUpperCase(),
        style: Palette.display(size: size * 0.46, color: c == Palette.balls[1] ? Palette.navy : Colors.white),
      ),
    );
  }
}

/// One ranked row: medal, avatar, name, moves.
class BoardRow extends StatelessWidget {
  final int rank;
  final BoardEntry e;

  /// On your row: the reactions friends sent you for this day.
  final List<Reaction> received;

  /// On a friend's row: the reaction you sent (index into [reactionEmoji]),
  /// and what to do when you pick one. No button when [onReact] is null.
  final int? sent;
  final ValueChanged<int>? onReact;
  const BoardRow({super.key, required this.rank, required this.e, this.received = const [], this.sent, this.onReact});

  @override
  Widget build(BuildContext context) {
    const medals = ['🥇', '🥈', '🥉'];
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: e.isMe ? Palette.picked : Palette.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: e.isMe ? Palette.gold : Palette.line, width: 1.5),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: Text(
              rank <= 3 ? medals[rank - 1] : '$rank',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Palette.inkSoft),
            ),
          ),
          const SizedBox(width: 6),
          Avatar(e.isMe ? (e.name.isEmpty ? 'Me' : e.name) : e.name, size: 32),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.isMe ? 'You' : e.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Palette.ink),
                ),
                Text(
                  [
                    e.attempts == 1 ? '1st try' : '${ordinal(e.attempts)} try',
                    if (e.streak >= 2) '🔥${e.streak}',
                  ].join('  ·  '),
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Palette.inkSoft),
                ),
                if (received.isNotEmpty)
                  Text(
                    received.map((r) => '${r.from} ${r.symbol}').join(', '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Palette.ink),
                  ),
              ],
            ),
          ),
          Text('${e.moves}', style: Palette.display(size: 22)),
          Text(
            ' moves',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Palette.inkSoft),
          ),
          if (onReact != null) ...[const SizedBox(width: 8), _ReactButton(sent: sent, onReact: onReact!)],
        ],
      ),
    );
  }
}

/// Today's friends board: everyone who sent you today's result, plus you.
class FriendsSheet extends StatefulWidget {
  final Storage storage;
  final Friends friends;
  final int today;

  /// Your own result today, if solved.
  final BoardEntry? me;

  /// Shares your result (or an invite if you haven't solved yet).
  final Future<void> Function() onInvite;

  final Reactions reactions;

  /// Sends a friend a reaction to today's result.
  final Future<void> Function(BoardEntry friend, int emoji) onReact;

  const FriendsSheet({
    super.key,
    required this.storage,
    required this.friends,
    required this.today,
    required this.me,
    required this.onInvite,
    required this.reactions,
    required this.onReact,
  });

  @override
  State<FriendsSheet> createState() => _FriendsSheetState();
}

class _FriendsSheetState extends State<FriendsSheet> {
  late final _name = TextEditingController(text: widget.storage.myName);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final today = widget.friends.forDay(widget.today);
    final rows = rankDay(today, me: widget.me);
    final waiting = widget.friends.names
        .where((n) => !today.any((r) => r.name.toLowerCase() == n.toLowerCase()))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SheetTitle('Friends today'),
        const SizedBox(height: 6),
        Text(
          widget.me == null && today.isNotEmpty
              ? 'Solve today\'s puzzle to take your place.'
              : 'Fewest moves wins. Tap 😊 to send a friend a reaction.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Palette.inkSoft),
        ),
        const SizedBox(height: 14),
        if (rows.isEmpty)
          const _EmptyBoard()
        else
          for (var i = 0; i < rows.length; i++)
            BoardRow(
              rank: i + 1,
              e: rows[i],
              received: rows[i].isMe ? widget.reactions.forDay(widget.today) : const [],
              sent: rows[i].isMe ? null : widget.reactions.sentTo(rows[i].name, widget.today),
              onReact: rows[i].isMe
                  ? null
                  : (emoji) async {
                      await widget.onReact(rows[i], emoji);
                      if (mounted) setState(() {});
                    },
            ),
        if (waiting.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'Waiting on ${waiting.take(4).join(', ')}${waiting.length > 4 ? ' and ${waiting.length - 4} more' : ''}',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Palette.inkSoft),
          ),
        ],
        const SizedBox(height: 18),
        BigButton(
          label: widget.me == null ? 'Invite friends' : 'Send my result',
          icon: Icons.ios_share_rounded,
          onTap: () async {
            await widget.onInvite();
            if (mounted) setState(() => _name.text = widget.storage.myName);
          },
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Text(
              'Your name',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Palette.inkSoft),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _name,
                maxLength: 16,
                textCapitalization: TextCapitalization.words,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Palette.ink),
                decoration: InputDecoration(
                  isDense: true,
                  counterText: '',
                  hintText: 'So friends know it\'s you',
                  filled: true,
                  fillColor: Palette.background,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                ),
                onChanged: (v) {
                  widget.storage.setMyName(cleanName(v));
                  widget.storage.setAskedName();
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _EmptyBoard extends StatelessWidget {
  const _EmptyBoard();
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(color: Palette.background, borderRadius: BorderRadius.circular(20)),
    child: Column(
      children: [
        Text('👋', style: TextStyle(fontSize: 34)),
        SizedBox(height: 6),
        Text(
          'Send your result to a friend or a group chat. When they solve and share back, they show up here, ranked.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, height: 1.35, fontWeight: FontWeight.w700, color: Palette.ink),
        ),
      ],
    ),
  );
}

/// The little "Ana solved it in 13" line above the board.
class FriendsChip extends StatelessWidget {
  final List<FriendResult> today;
  final int? myMoves;
  final VoidCallback onTap;
  const FriendsChip({super.key, required this.today, required this.myMoves, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final best = [...today]..sort((a, b) => a.moves.compareTo(b.moves));
    final top = best.first;
    final others = today.length - 1;
    final String text;
    if (myMoves == null) {
      text = others == 0
          ? '${top.name} solved it in ${top.moves}. Beat that!'
          : '${top.name} leads with ${top.moves} moves · ${others + 1} friends played';
    } else {
      final beaten = today.where((f) => f.moves > myMoves!).length;
      text = beaten == today.length
          ? 'You\'re top of your friends today!'
          : 'You beat $beaten of ${today.length} ${today.length == 1 ? 'friend' : 'friends'} today';
    }
    return Squish(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(4, 4, 14, 4),
          decoration: BoxDecoration(
            color: Palette.card,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Palette.tubeStroke, width: 1.5),
            boxShadow: const [BoxShadow(color: Color(0x1A241A10), blurRadius: 8, offset: Offset(0, 3))],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 24.0 + 14 * (best.length.clamp(1, 3) - 1),
                height: 24,
                child: Stack(
                  children: [
                    for (var i = 0; i < best.length.clamp(1, 3); i++)
                      Positioned(left: i * 14.0, child: Avatar(best[i].name, size: 24)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Palette.ink),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Send a friend a reaction to their result: 👏 🔥 😮 😂.
class _ReactButton extends StatelessWidget {
  final int? sent;
  final ValueChanged<int> onReact;
  const _ReactButton({required this.sent, required this.onReact});

  @override
  Widget build(BuildContext context) => PopupMenuButton<int>(
    tooltip: 'React',
    onSelected: onReact,
    color: Palette.card,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    position: PopupMenuPosition.under,
    itemBuilder: (_) => [
      for (var i = 0; i < reactionEmoji.length; i++)
        PopupMenuItem<int>(
          value: i,
          height: 44,
          child: Text(reactionEmoji[i], style: const TextStyle(fontSize: 24)),
        ),
    ],
    child: Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: sent == null ? Palette.panel : Palette.picked,
        border: Border.all(color: sent == null ? Palette.line : Palette.gold, width: 1.5),
      ),
      child: sent == null
          ? Icon(Icons.add_reaction_outlined, size: 19, color: Palette.inkSoft)
          : Text(reactionEmoji[sent!], style: const TextStyle(fontSize: 18)),
    ),
  );
}
