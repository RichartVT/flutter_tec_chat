// lib/features/chats/presentation/screens/chat_detail_screen.dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

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
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  final _messageCtrl = TextEditingController();
  bool _sending = false;

  // Cache de usuarios (para mostrar nombres en grupo)
  final Map<String, AppUser> _usersCache = {};

  @override
  void dispose() {
    _messageCtrl.dispose();
    super.dispose();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _messagesStream(String chatId) {
    return _db
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  Future<void> _sendTextMessage() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final text = _messageCtrl.text.trim();
    if (text.isEmpty) return;

    setState(() => _sending = true);

    try {
      final ref = _db
          .collection('chats')
          .doc(widget.chatId)
          .collection('messages')
          .doc();

      await ref.set({
        'id': ref.id,
        'fromId': user.uid,
        'type': 'text',
        'text': text,
        'mediaData': null,
        'mediaMime': null,
        'mediaName': null,
        'createdAt': FieldValue.serverTimestamp(),
      });

      await _db.collection('chats').doc(widget.chatId).update({
        'lastMessage': text,
        'lastMessageAt': FieldValue.serverTimestamp(),
      });

      _messageCtrl.clear();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al enviar mensaje: $e')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendImageFromDevice() async {
    final user = _auth.currentUser;
    if (user == null) return;

    // Abrir selector de archivos (imágenes / gif)
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'gif'],
      withData: true, // importante para web
    );

    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudieron leer los datos del archivo.'),
        ),
      );
      return;
    }

    // ⚠️ Esto guarda la imagen en base64 en Firestore.
    // Para una app real con muchas imágenes, lo ideal es usar Firebase Storage.
    final base64Data = base64Encode(bytes);

    final ext = (file.extension ?? '').toLowerCase();
    final isGif = ext == 'gif';
    final type = isGif ? 'gif' : 'image';

    setState(() => _sending = true);

    try {
      final ref = _db
          .collection('chats')
          .doc(widget.chatId)
          .collection('messages')
          .doc();

      await ref.set({
        'id': ref.id,
        'fromId': user.uid,
        'type': type,
        'text': null,
        'mediaData': base64Data,
        'mediaName': file.name,
        'createdAt': FieldValue.serverTimestamp(),
      });

      final preview = isGif ? '[Animación]' : '[Imagen]';

      await _db.collection('chats').doc(widget.chatId).update({
        'lastMessage': preview,
        'lastMessageAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al enviar imagen: $e')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<AppUser?> _loadUser(String uid) async {
    if (_usersCache.containsKey(uid)) {
      return _usersCache[uid];
    }
    try {
      final snap = await _db.collection('users').doc(uid).get();
      if (!snap.exists) return null;
      final data = snap.data() as Map<String, dynamic>;
      final user = AppUser.fromMap(data, snap.id);
      _usersCache[uid] = user;
      return user;
    } catch (_) {
      return null;
    }
  }

  String _displayNameFor(AppUser? user) {
    if (user == null) return 'User';
    final name = user.displayName?.trim();
    if (name != null && name.isNotEmpty) return name;
    return 'User';
  }

  void _insertEmoji(String emoji) {
    final text = _messageCtrl.text;
    _messageCtrl.text = '$text$emoji';
    _messageCtrl.selection = TextSelection.fromPosition(
      TextPosition(offset: _messageCtrl.text.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = _auth.currentUser;
    final title = widget.isGroup
        ? 'Chat de grupo'
        : (widget.otherUser?.displayName ??
              widget.otherUser?.emailTec ??
              'Chat');

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _messagesStream(widget.chatId),
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
                      'No hay mensajes todavía.\nEscribe el primero.',
                      textAlign: TextAlign.center,
                    ),
                  );
                }

                return ListView.builder(
                  reverse: true,
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final msg = docs[index].data();
                    final fromId = msg['fromId'] as String?;
                    final isMe =
                        currentUser != null && currentUser.uid == fromId;

                    final type = msg['type'] as String? ?? 'text';
                    final text = msg['text'] as String?;
                    final mediaData = msg['mediaData'] as String?;
                    final ts = msg['createdAt'] as Timestamp?;
                    final time = ts?.toDate();

                    Widget bubbleContent;

                    if ((type == 'image' || type == 'gif') &&
                        mediaData != null &&
                        mediaData.isNotEmpty) {
                      try {
                        final Uint8List bytes = base64Decode(mediaData);
                        bubbleContent = ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.memory(
                            bytes,
                            width: 220,
                            fit: BoxFit.cover,
                          ),
                        );
                      } catch (_) {
                        bubbleContent = const Text(
                          'No se pudo mostrar la imagen.',
                        );
                      }
                    } else {
                      bubbleContent = Text(
                        text ?? '',
                        style: const TextStyle(fontSize: 16),
                      );
                    }

                    final bubble = Container(
                      margin: const EdgeInsets.symmetric(
                        vertical: 4,
                        horizontal: 8,
                      ),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isMe
                            ? Colors.teal.shade100
                            : Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Nombre del remitente en grupo (sin teléfono)
                          if (widget.isGroup && !isMe && fromId != null)
                            FutureBuilder<AppUser?>(
                              future: _loadUser(fromId),
                              builder: (context, snap) {
                                final user = snap.data;
                                final name = _displayNameFor(user);
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 4.0),
                                  child: Text(
                                    name,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                );
                              },
                            ),
                          bubbleContent,
                          if (time != null)
                            Align(
                              alignment: Alignment.bottomRight,
                              child: Text(
                                '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey,
                                ),
                              ),
                            ),
                        ],
                      ),
                    );

                    return Align(
                      alignment: isMe
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: bubble,
                    );
                  },
                );
              },
            ),
          ),

          // Barra inferior
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              child: Row(
                children: [
                  // Emojis rápidos
                  IconButton(
                    icon: const Text('😊', style: TextStyle(fontSize: 22)),
                    onPressed: () {
                      showModalBottomSheet(
                        context: context,
                        showDragHandle: true,
                        builder: (_) {
                          return SafeArea(
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children:
                                      [
                                        '😀',
                                        '😂',
                                        '😍',
                                        '👍',
                                        '🎓',
                                        '📚',
                                        '🔥',
                                        '🤓',
                                      ].map((e) {
                                        return InkWell(
                                          onTap: () {
                                            Navigator.pop(context);
                                            _insertEmoji(e);
                                          },
                                          child: Padding(
                                            padding: const EdgeInsets.all(8.0),
                                            child: Text(
                                              e,
                                              style: const TextStyle(
                                                fontSize: 24,
                                              ),
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),

                  // Adjuntar imagen / gif desde dispositivo
                  IconButton(
                    icon: const Icon(Icons.photo),
                    onPressed: _sending ? null : _sendImageFromDevice,
                  ),

                  Expanded(
                    child: TextField(
                      controller: _messageCtrl,
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.newline,
                      decoration: const InputDecoration(
                        hintText: 'Escribe un mensaje',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(24)),
                        ),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  IconButton(
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                    onPressed: _sending ? null : _sendTextMessage,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
