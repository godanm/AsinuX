import 'dart:async';
import 'package:flutter/material.dart';
import '../models/chat_message.dart';
import '../services/firebase_service.dart';

// ── Pre-populated quick messages ─────────────────────────────────────────────

const _quickTexts = [
  'Play Fast',      'Please don\'t hit', 'Hi!',
  'Take that!',     'I\'m winning',      'Smart Move',
  'You are Donkey today', 'Thanks',       'Well played!',
  'I\'m the Donkey this time', 'Wrong Move!', 'Love this game!',
  'Awesome!',       'Don\'t have that card', 'Bye!',
];

const _quickEmojis = [
  '😆', '😂', '😈',
  '😡', '😭', '😮',
  '🤔', '😅', '😎',
];

// ── Entry point ──────────────────────────────────────────────────────────────

void showChatOverlay(
  BuildContext context, {
  required String roomId,
  required String senderId,
  required String senderName,
}) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _ChatSheet(
      roomId: roomId,
      senderId: senderId,
      senderName: senderName,
    ),
  );
}

// ── Sheet ────────────────────────────────────────────────────────────────────

class _ChatSheet extends StatefulWidget {
  final String roomId;
  final String senderId;
  final String senderName;

  const _ChatSheet({
    required this.roomId,
    required this.senderId,
    required this.senderName,
  });

  @override
  State<_ChatSheet> createState() => _ChatSheetState();
}

class _ChatSheetState extends State<_ChatSheet> {
  final ScrollController _scrollCtrl = ScrollController();
  List<ChatMessage> _messages = [];
  StreamSubscription<List<ChatMessage>>? _sub;
  @override
  void initState() {
    super.initState();
    _sub = FirebaseService.instance
        .chatStream(widget.roomId)
        .listen((msgs) {
      if (!mounted) return;
      setState(() => _messages = msgs);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollCtrl.hasClients) {
          _scrollCtrl.animateTo(
            _scrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _send(String message) async {
    await FirebaseService.instance.sendChatMessage(
      roomId: widget.roomId,
      senderId: widget.senderId,
      senderName: widget.senderName,
      message: message,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: Color(0xFF1a0040),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // ── Header ──────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
            child: Row(
              children: [
                const Spacer(),
                const Text(
                  'CHAT',
                  style: TextStyle(
                    color: Color(0xFFFFD700),
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    letterSpacing: 3,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white54),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          // ── Message feed ────────────────────────────────────
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Text(
                      'Tap a message to send',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.3),
                          fontSize: 13),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: _messages.length,
                    itemBuilder: (_, i) {
                      final msg = _messages[i];
                      final isMe = msg.senderId == widget.senderId;
                      return _MessageBubble(msg: msg, isMe: isMe);
                    },
                  ),
          ),

          const Divider(color: Colors.white12, height: 1),

          // ── Quick text grid ──────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: 2.6,
                crossAxisSpacing: 6,
                mainAxisSpacing: 6,
              ),
              itemCount: _quickTexts.length,
              itemBuilder: (_, i) => _QuickBtn(
                label: _quickTexts[i],
                onTap: () => _send(_quickTexts[i]),
              ),
            ),
          ),

          // ── Emoji grid ───────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 9,
                childAspectRatio: 1,
                crossAxisSpacing: 4,
                mainAxisSpacing: 4,
              ),
              itemCount: _quickEmojis.length,
              itemBuilder: (_, i) => GestureDetector(
                onTap: () => _send(_quickEmojis[i]),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(_quickEmojis[i],
                        style: const TextStyle(fontSize: 20)),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Message bubble ────────────────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  final ChatMessage msg;
  final bool isMe;

  const _MessageBubble({required this.msg, required this.isMe});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            CircleAvatar(
              radius: 12,
              backgroundColor: const Color(0xFF4a0080),
              child: Text(
                msg.senderName.isNotEmpty ? msg.senderName[0].toUpperCase() : '?',
                style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 6),
          ],
          Column(
            crossAxisAlignment:
                isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (!isMe)
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 2),
                  child: Text(
                    msg.senderName,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 10),
                  ),
                ),
              Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.55,
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: isMe
                      ? const Color(0xFF6a00cc)
                      : const Color(0xFF2e0060),
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(14),
                    topRight: const Radius.circular(14),
                    bottomLeft: Radius.circular(isMe ? 14 : 4),
                    bottomRight: Radius.circular(isMe ? 4 : 14),
                  ),
                ),
                child: Text(
                  msg.message,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
            ],
          ),
          if (isMe) const SizedBox(width: 4),
        ],
      ),
    );
  }
}

// ── Quick message button ──────────────────────────────────────────────────────

class _QuickBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _QuickBtn({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF2e0060),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
