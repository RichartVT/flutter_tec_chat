import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import './add_contact_screen.dart';
import './models/app_user_contact.dart'; // lo hacemos más abajo
import './utils/contact_helpers.dart'; // también más abajo
import './widgets/contact_tile.dart'; // también más abajo

class ContactsListScreen extends StatelessWidget {
  const ContactsListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      return const Scaffold(
        body: Center(child: Text('No hay sesión iniciada.')),
      );
    }

    final contactsStream = FirebaseFirestore.instance
        .collection('contacts')
        .where('ownerId', isEqualTo: currentUser.uid)
        .snapshots();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Contactos'),
        actions: [
          IconButton(
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AddContactScreen()),
              );
            },
            icon: const Icon(Icons.person_add),
            tooltip: 'Agregar contacto',
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: contactsStream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Error al cargar contactos:\n${snapshot.error}',
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
                'No tienes contactos agregados.\nUsa el botón de arriba para añadir.',
                textAlign: TextAlign.center,
              ),
            );
          }

          return ListView.separated(
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(height: 0),
            itemBuilder: (context, index) {
              final contactDoc = docs[index];
              final contactId = contactDoc['contactId'] as String?;
              if (contactId == null) {
                return const SizedBox.shrink();
              }

              return FutureBuilder<AppUserContact?>(
                future: loadContactUser(contactId),
                builder: (context, snapshotUser) {
                  if (snapshotUser.connectionState == ConnectionState.waiting) {
                    return const ListTile(
                      leading: CircleAvatar(child: Icon(Icons.person)),
                      title: Text('Cargando...'),
                    );
                  }

                  final contactUser = snapshotUser.data;
                  if (contactUser == null) {
                    return const ListTile(
                      leading: CircleAvatar(child: Icon(Icons.person_off)),
                      title: Text('Usuario no disponible'),
                    );
                  }

                  return ContactTile(user: contactUser);
                },
              );
            },
          );
        },
      ),
    );
  }
}
