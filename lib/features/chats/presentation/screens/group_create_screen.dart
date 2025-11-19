// lib/features/chats/presentation/screens/group_create_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../../data/models/app_user.dart';
import 'chat_detail_screen.dart';

class GroupCreateScreen extends StatefulWidget {
  const GroupCreateScreen({super.key});

  @override
  State<GroupCreateScreen> createState() => _GroupCreateScreenState();
}

class _GroupCreateScreenState extends State<GroupCreateScreen> {
  final _groupNameCtrl = TextEditingController();
  bool _loading = true;
  bool _creating = false;

  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  AppUser? _currentUser;
  final Map<String, AppUser> _possibleMembers = {};
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _groupNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final user = _auth.currentUser;
    if (user == null) {
      setState(() => _loading = false);
      return;
    }

    try {
      // 1) Obtener usuario actual
      final meSnap = await _db.collection('users').doc(user.uid).get();
      if (!meSnap.exists) {
        setState(() => _loading = false);
        return;
      }

      final me = AppUser.fromMap(meSnap.data()!, meSnap.id);
      _currentUser = me;

      // Si no es profesor, no hace falta cargar contactos
      if (me.role != 'teacher') {
        setState(() => _loading = false);
        return;
      }

      // 2) Cargar contactos (alumnos) del profesor
      final contactsSnap = await _db
          .collection('contacts')
          .where('ownerId', isEqualTo: user.uid)
          .get();

      for (final c in contactsSnap.docs) {
        final otherId = c['contactId'] as String;
        final otherSnap = await _db.collection('users').doc(otherId).get();
        if (!otherSnap.exists) continue;
        final otherUser = AppUser.fromMap(otherSnap.data()!, otherSnap.id);
        _possibleMembers[otherUser.uid] = otherUser;
      }

      setState(() => _loading = false);
    } catch (e) {
      debugPrint('Error cargando datos para grupo: $e');
      setState(() => _loading = false);
    }
  }

  Future<void> _createGroup() async {
    if (_currentUser == null || _currentUser!.role != 'teacher') return;

    final name = _groupNameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresa un nombre para el grupo.')),
      );
      return;
    }

    if (_selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecciona al menos un alumno para el grupo.'),
        ),
      );
      return;
    }

    setState(() => _creating = true);

    try {
      final members = <String>[_currentUser!.uid, ..._selected];

      final chatRef = _db.collection('chats').doc();

      await chatRef.set({
        'id': chatRef.id,
        'title': name,
        'isGroup': true,
        'hidePhones': true, // los alumnos no ven teléfonos
        'members': members,
        'createdBy': _currentUser!.uid,
        'createdAt': FieldValue.serverTimestamp(),
        'lastMessage': null,
        'lastMessageAt': null,
      });

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ChatDetailScreen(chatId: chatRef.id, isGroup: true),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al crear grupo: $e')));
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 🔄 Estado de carga inicial
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Nuevo grupo')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    // 🚫 Si no hay usuario o no es profesor
    if (_currentUser?.role != 'teacher') {
      return Scaffold(
        appBar: AppBar(title: const Text('Nuevo grupo')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Solo los profesores pueden crear grupos.\n'
              'Pide a tu profesor que cree el grupo.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    // ✅ Vista normal de creación de grupo
    return Scaffold(
      appBar: AppBar(title: const Text('Nuevo grupo')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _groupNameCtrl,
              decoration: const InputDecoration(
                labelText: 'Nombre del grupo',
                hintText: 'Ej. ISC 5°A Programación',
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _possibleMembers.isEmpty
                  ? const Center(
                      child: Text(
                        'No tienes contactos para agregar.\n'
                        'Primero agrega alumnos a tu lista de contactos.',
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView(
                      children: _possibleMembers.values.map((u) {
                        final name =
                            (u.displayName != null &&
                                u.displayName!.trim().isNotEmpty)
                            ? u.displayName!
                            : 'User'; // 👈 si no hay nombre, "User"

                        final selected = _selected.contains(u.uid);

                        return CheckboxListTile(
                          value: selected,
                          onChanged: (v) {
                            setState(() {
                              if (v == true) {
                                _selected.add(u.uid);
                              } else {
                                _selected.remove(u.uid);
                              }
                            });
                          },
                          title: Text(name),
                          // OJO: aquí NO mostramos teléfonos
                          subtitle: u.emailTec != null
                              ? Text(u.emailTec!)
                              : null,
                        );
                      }).toList(),
                    ),
            ),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _creating ? null : _createGroup,
                icon: _creating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check),
                label: Text(_creating ? 'Creando...' : 'Crear grupo'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
