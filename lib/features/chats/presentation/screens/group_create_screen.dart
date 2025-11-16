import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../../data/models/app_user.dart';

class GroupCreateScreen extends StatefulWidget {
  const GroupCreateScreen({super.key});

  @override
  State<GroupCreateScreen> createState() => _GroupCreateScreenState();
}

class _GroupCreateScreenState extends State<GroupCreateScreen> {
  final _groupNameCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _hidePhones = true;
  bool _creating = false;
  bool _loadingRole = true;
  bool _isProfessor = false;

  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  final Set<String> _selectedUserIds = {};

  @override
  void initState() {
    super.initState();
    _loadCurrentUserRole();
  }

  @override
  void dispose() {
    _groupNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentUserRole() async {
    final user = _auth.currentUser;
    if (user == null) {
      setState(() {
        _loadingRole = false;
        _isProfessor = false;
      });
      return;
    }

    final doc = await _firestore.collection('users').doc(user.uid).get();
    final data = doc.data() ?? {};

    final role = (data['role'] as String?) ?? 'alumno';

    setState(() {
      _loadingRole = false;
      _isProfessor = role == 'profesor';
    });
  }

  Future<void> _createGroup() async {
    if (!_formKey.currentState!.validate()) return;

    final user = _auth.currentUser;
    if (user == null) return;

    if (_selectedUserIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona al menos un integrante.')),
      );
      return;
    }

    setState(() => _creating = true);

    try {
      final members = <String>{user.uid, ..._selectedUserIds}.toList();

      final chatRef = await _firestore.collection('chats').add({
        'isGroup': true,
        'title': _groupNameCtrl.text.trim(),
        'createdBy': user.uid,
        'members': members,
        'hidePhones': _hidePhones,
        'lastMessage': 'Grupo creado',
        'lastMessageAt': FieldValue.serverTimestamp(),
      });

      await chatRef.collection('messages').add({
        'senderId': user.uid,
        'text': 'Grupo creado por el profesor.',
        'type': 'text',
        'mediaUrl': null,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Grupo creado correctamente.')),
      );

      Navigator.pop(context);
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
    final currentUser = _auth.currentUser;

    if (currentUser == null) {
      return const Scaffold(
        body: Center(child: Text('No hay sesión iniciada.')),
      );
    }

    if (_loadingRole) {
      return Scaffold(
        appBar: AppBar(title: const Text('Nuevo grupo')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (!_isProfessor) {
      return Scaffold(
        appBar: AppBar(title: const Text('Nuevo grupo')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Solo los usuarios con rol "profesor" pueden crear grupos.\n'
              'Pide al profesor que inicie sesión para crear el grupo.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final usersStream = _firestore
        .collection('users')
        .where('role', isEqualTo: 'alumno')
        .orderBy('displayName', descending: false)
        .snapshots();

    return Scaffold(
      appBar: AppBar(title: const Text('Nuevo grupo')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  TextFormField(
                    controller: _groupNameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Nombre del grupo',
                      hintText: 'Ej. BD 7A, Móvil ISC...',
                    ),
                    validator: (value) {
                      final v = value?.trim() ?? '';
                      if (v.isEmpty) return 'Ingresa un nombre para el grupo.';
                      if (v.length < 3) return 'El nombre es muy corto.';
                      return null;
                    },
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    title: const Text('Ocultar números telefónicos'),
                    subtitle: const Text(
                      'Si está activo, los teléfonos de los integrantes no se mostrarán '
                      'en la información del grupo.',
                    ),
                    value: _hidePhones,
                    onChanged: (v) {
                      setState(() => _hidePhones = v);
                    },
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Selecciona integrantes',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 0),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: usersStream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Error al cargar usuarios:\n${snapshot.error}',
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
                      'No se encontraron alumnos registrados.\n'
                      'Asegúrate de que ya hayan iniciado sesión en la app.',
                      textAlign: TextAlign.center,
                    ),
                  );
                }

                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];

                    if (doc.id == currentUser.uid) {
                      return const SizedBox.shrink();
                    }

                    final data = doc.data();
                    final user = AppUser.fromMap(data, doc.id);

                    final name =
                        user.displayName ??
                        user.emailTec ??
                        user.phoneNumber ??
                        'Alumno';

                    final selected = _selectedUserIds.contains(user.uid);

                    return CheckboxListTile(
                      value: selected,
                      onChanged: (v) {
                        setState(() {
                          if (v == true) {
                            _selectedUserIds.add(user.uid);
                          } else {
                            _selectedUserIds.remove(user.uid);
                          }
                        });
                      },
                      title: Text(name),
                      subtitle: Text(user.emailTec ?? (user.phoneNumber ?? '')),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: _creating
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check),
                  label: Text(_creating ? 'Creando grupo...' : 'Crear grupo'),
                  onPressed: _creating ? null : _createGroup,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
