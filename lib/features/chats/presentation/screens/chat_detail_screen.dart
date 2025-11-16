import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../data/models/app_user.dart';

class ChatDetailScreen extends StatefulWidget {
  final String chatId;
  final bool isGroup;
  final AppUser? otherUser;

  const ChatDetailScreen({
    super.key,
    required this.chatId,
    required this.isGroup,
    this.otherUser,
  });

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  final _messageCtrl = TextEditingController();
  final _scrollController = ScrollController();

  bool _sendingText = false;
  bool _sendingImage = false;

  User? get _currentUser => FirebaseAuth.instance.currentUser;

  @override
  void dispose() {
    _messageCtrl.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  CollectionReference<Map<String, dynamic>> get _messagesRef =>
      FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .collection('messages');

  DocumentReference<Map<String, dynamic>> get _chatRef =>
      FirebaseFirestore.instance.collection('chats').doc(widget.chatId);

  Future<void> _sendTextMessage() async {
    final user = _currentUser;
    if (user == null) return;

    final text = _messageCtrl.text.trim();
    if (text.isEmpty) return;

    setState(() => _sendingText = true);

    try {
      await _messagesRef.add({
        'senderId': user.uid,
        'text': text,
        'type': 'text',
        'mediaUrl': null,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Actualizamos el resumen del chat
      await _chatRef.update({
        'lastMessage': text,
        'lastMessageAt': FieldValue.serverTimestamp(),
      });

      _messageCtrl.clear();
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al enviar mensaje: $e')));
    } finally {
      if (mounted) {
        setState(() => _sendingText = false);
      }
    }
  }

  Future<void> _pickAndSendImage() async {
    final user = _currentUser;
    if (user == null) return;

    final picker = ImagePicker();

    try {
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 75,
      );

      if (picked == null) return;

      setState(() => _sendingImage = true);

      final file = File(picked.path);

      final fileName =
          '${DateTime.now().millisecondsSinceEpoch}_${user.uid}.jpg';

      final ref = FirebaseStorage.instance
          .ref()
          .child('chats')
          .child(widget.chatId)
          .child('images')
          .child(fileName);

      await ref.putFile(file);
      final url = await ref.getDownloadURL();

      await _messagesRef.add({
        'senderId': user.uid,
        'text': null,
        'type': 'image',
        'mediaUrl': url,
        'createdAt': FieldValue.serverTimestamp(),
      });

      await _chatRef.update({
        'lastMessage': '📷 Foto',
        'lastMessageAt': FieldValue.serverTimestamp(),
      });

      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al enviar imagen: $e')));
    } finally {
      if (mounted) {
        setState(() => _sendingImage = false);
      }
    }
  }

  void _scrollToBottom() {
    // El ListView está con reverse: true, así que usamos posición 0
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  String _buildTitle() {
    if (widget.isGroup) {
      // Más adelante puedes cargar el título real desde el doc del chat.
      return 'Grupo';
    }
    final u = widget.otherUser;
    return u?.displayName ?? u?.emailTec ?? u?.phoneNumber ?? 'Chat';
  }

  @override
  Widget build(BuildContext context) {
    if (_currentUser == null) {
      return const Scaffold(
        body: Center(child: Text('No hay sesión iniciada')),
      );
    }

    final messagesStream = _messagesRef
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots();

    return Scaffold(
      appBar: AppBar(title: Text(_buildTitle())),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: messagesStream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Error al cargar mensajes:\n${snapshot.error}',
                      textAlign: TextAlign.center,
                    ),
                  );
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snapshot.data?.docs ?? [];

                if (docs.isEmpty) {
                  return const Center(
                    child: Text(
                      'No hay mensajes.\nEscribe el primero.',
                      textAlign: TextAlign.center,
                    ),
                  );
                }

                return ListView.builder(
                  controller: _scrollController,
                  reverse: true, // Mensajes recientes abajo
                  itemCount: docs.length,
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 8,
                  ),
                  itemBuilder: (context, index) {
                    final msg = docs[index].data();
                    final isMe = msg['senderId'] == _currentUser!.uid;
                    return _MessageBubble(
                      isMe: isMe,
                      text: msg['text'] as String?,
                      type: msg['type'] as String? ?? 'text',
                      mediaUrl: msg['mediaUrl'] as String?,
                      createdAt: (msg['createdAt'] as Timestamp?)?.toDate(),
                    );
                  },
                );
              },
            ),
          ),
          _MessageInputArea(
            controller: _messageCtrl,
            sendingText: _sendingText,
            sendingImage: _sendingImage,
            onSendText: _sendTextMessage,
            onSendImage: _pickAndSendImage,
          ),
        ],
      ),
    );
  }
}

/// Burbujas de mensaje (texto o imagen)
class _MessageBubble extends StatelessWidget {
  final bool isMe;
  final String? text;
  final String type;
  final String? mediaUrl;
  final DateTime? createdAt;

  const _MessageBubble({
    required this.isMe,
    required this.text,
    required this.type,
    required this.mediaUrl,
    required this.createdAt,
  });

  String _formatTime(DateTime? time) {
    if (time == null) return '';
    final hh = time.hour.toString().padLeft(2, '0');
    final mm = time.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = isMe ? const Color(0xFFDCF8C6) : Colors.white;
    final align = isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(16),
      topRight: const Radius.circular(16),
      bottomLeft: Radius.circular(isMe ? 16 : 0),
      bottomRight: Radius.circular(isMe ? 0 : 16),
    );

    Widget content;

    if (type == 'image' && mediaUrl != null) {
      content = Column(
        crossAxisAlignment: align,
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(mediaUrl!, width: 220, fit: BoxFit.cover),
          ),
          if (text != null && text!.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(text!),
          ],
          const SizedBox(height: 4),
          Text(
            _formatTime(createdAt),
            style: const TextStyle(fontSize: 10, color: Colors.grey),
          ),
        ],
      );
    } else {
      content = Column(
        crossAxisAlignment: align,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text ?? '', style: const TextStyle(fontSize: 15)),
          const SizedBox(height: 4),
          Text(
            _formatTime(createdAt),
            style: const TextStyle(fontSize: 10, color: Colors.grey),
          ),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
      child: Row(
        mainAxisAlignment: isMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
              decoration: BoxDecoration(color: bgColor, borderRadius: radius),
              child: content,
            ),
          ),
        ],
      ),
    );
  }
}

/// Barra inferior: input de texto + botones
class _MessageInputArea extends StatelessWidget {
  final TextEditingController controller;
  final bool sendingText;
  final bool sendingImage;
  final VoidCallback onSendText;
  final VoidCallback onSendImage;

  const _MessageInputArea({
    required this.controller,
    required this.sendingText,
    required this.sendingImage,
    required this.onSendText,
    required this.onSendImage,
  });

  @override
  Widget build(BuildContext context) {
    final canSend = !sendingText && controller.text.trim().isNotEmpty;

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFE0E0E0))),
        ),
        child: Row(
          children: [
            IconButton(
              icon: sendingImage
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.image),
              onPressed: sendingImage ? null : onSendImage,
            ),
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 5,
                decoration: const InputDecoration(
                  hintText: 'Escribe un mensaje',
                  border: InputBorder.none,
                ),
                onChanged: (_) {
                  // Para redibujar el botón de enviar cuando hay texto/no hay texto
                  (context as Element).markNeedsBuild();
                },
              ),
            ),
            IconButton(
              icon: sendingText
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(canSend ? Icons.send : Icons.mic),
              onPressed: canSend ? onSendText : null,
            ),
          ],
        ),
      ),
    );
  }
}
