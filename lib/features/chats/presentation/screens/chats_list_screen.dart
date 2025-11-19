// lib/features/chats/presentation/screens/chats_list_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'chat_detail_screen.dart';
import 'group_create_screen.dart';
import '../../../../contacts/contacts_list_screen.dart';
import '../../../../data/models/app_user.dart';
import '../../../../profile/profile_screen.dart';

class ChatsListScreen extends StatefulWidget {
  const ChatsListScreen({super.key});

  @override
  State<ChatsListScreen> createState() => _ChatsListScreenState();
}

class _ChatsListScreenState extends State<ChatsListScreen> {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  User? _firebaseUser;
  bool _isTeacher = false;
  bool _loadingRole = true;

  @override
  void initState() {
    super.initState();
    _firebaseUser = _auth.currentUser;
    _loadUserRole();
  }

  Future<void> _loadUserRole() async {
    final user = _firebaseUser ?? _auth.currentUser;
    if (user == null) {
      setState(() => _loadingRole = false);
      return;
    }

    try {
      final snap = await _db.collection('users').doc(user.uid).get();
      final data = snap.data();
      if (data != null) {
        final role = data['role'] as String?;
        _isTeacher = role == 'teacher';
      }
    } catch (e) {
      debugPrint('Error cargando rol de usuario: $e');
    } finally {
      if (mounted) {
        setState(() => _loadingRole = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = _firebaseUser ?? _auth.currentUser;

    if (currentUser == null) {
      return const Scaffold(
        body: Center(
          child: Text(
            'No hay sesión iniciada.\nVuelve a la pantalla de inicio de sesión.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final uid = currentUser.uid;

    final chatsStream = _db
        .collection('chats')
        .where('members', arrayContains: uid)
        .orderBy('lastMessageAt', descending: true)
        .snapshots();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Conversaciones'),
        actions: [
          IconButton(
            icon: const Icon(Icons.contacts),
            tooltip: 'Contactos',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ContactsListScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.person),
            tooltip: 'Perfil',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProfileScreen()),
              );
            },
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: chatsStream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Error al cargar las conversaciones:\n${snapshot.error}',
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
                'No tienes conversaciones todavía.\nToca el botón para iniciar un chat.',
                textAlign: TextAlign.center,
              ),
            );
          }

          return ListView.separated(
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(height: 0),
            itemBuilder: (context, index) {
              final chatDoc = docs[index];
              return ChatListItem(chatDoc: chatDoc, currentUid: uid);
            },
          );
        },
      ),

      // 👇 Solo lo ve el profesor (role == 'teacher')
      floatingActionButton: _isTeacher
          ? FloatingActionButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const GroupCreateScreen()),
                );
              },
              child: const Icon(Icons.group_add),
            )
          : null,
    );
  }
}

class ChatListItem extends StatelessWidget {
  final DocumentSnapshot chatDoc;
  final String currentUid;

  const ChatListItem({
    super.key,
    required this.chatDoc,
    required this.currentUid,
  });

  @override
  Widget build(BuildContext context) {
    final data = chatDoc.data() as Map<String, dynamic>? ?? {};

    final bool isGroup = (data['isGroup'] as bool?) ?? false;
    final String? title = data['title'] as String?;
    final String? lastMessage = data['lastMessage'] as String?;
    final Timestamp? lastMessageAtTs = data['lastMessageAt'] as Timestamp?;
    final DateTime? lastMessageAt = lastMessageAtTs?.toDate();

    final List<dynamic> membersRaw = data['members'] as List<dynamic>? ?? [];
    final List<String> members = membersRaw
        .map((e) => e.toString())
        .toList(growable: false);

    // Grupo
    if (isGroup) {
      return ListTile(
        leading: const CircleAvatar(child: Icon(Icons.group)),
        title: Text(title ?? 'Grupo sin nombre'),
        subtitle: Text(
          lastMessage ?? 'Sin mensajes aún',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: lastMessageAt != null
            ? Text(
                _formatTime(lastMessageAt),
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              )
            : null,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  ChatDetailScreen(chatId: chatDoc.id, isGroup: true),
            ),
          );
        },
      );
    }

    // Chat individual
    String? otherUid;
    for (final m in members) {
      if (m != currentUid) {
        otherUid = m;
        break;
      }
    }
    otherUid ??= currentUid;

    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance
          .collection('users')
          .doc(otherUid)
          .get(),
      builder: (context, snapshot) {
        AppUser? otherUser;

        if (snapshot.hasData && snapshot.data!.exists) {
          final userData = snapshot.data!.data() as Map<String, dynamic>? ?? {};
          otherUser = AppUser.fromMap(userData, snapshot.data!.id);
        }

        final displayName =
            otherUser?.displayName ??
            otherUser?.emailTec ??
            otherUser?.phoneNumber ??
            'Contacto';

        final avatarUrl = otherUser?.avatarUrl;

        return ListTile(
          leading: CircleAvatar(
            backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
            child: avatarUrl == null
                ? Text(
                    displayName.isNotEmpty
                        ? displayName.characters.first.toUpperCase()
                        : '?',
                  )
                : null,
          ),
          title: Text(displayName),
          subtitle: Text(
            lastMessage ?? 'Sin mensajes aún',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: lastMessageAt != null
              ? Text(
                  _formatTime(lastMessageAt),
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                )
              : null,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ChatDetailScreen(
                  chatId: chatDoc.id,
                  isGroup: false,
                  otherUser: otherUser,
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final isToday =
        now.year == time.year && now.month == time.month && now.day == time.day;

    if (isToday) {
      final hh = time.hour.toString().padLeft(2, '0');
      final mm = time.minute.toString().padLeft(2, '0');
      return '$hh:$mm';
    } else {
      final dd = time.day.toString().padLeft(2, '0');
      final mm = time.month.toString().padLeft(2, '0');
      return '$dd/$mm';
    }
  }
}
