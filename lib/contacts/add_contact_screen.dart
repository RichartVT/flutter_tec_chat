import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class AddContactScreen extends StatefulWidget {
  const AddContactScreen({super.key});

  @override
  State<AddContactScreen> createState() => _AddContactScreenState();
}

class _AddContactScreenState extends State<AddContactScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();

  bool _adding = false;

  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  String _normalizePhone(String raw) {
    String phone = raw.trim();
    if (phone.isEmpty) return phone;

    if (!phone.startsWith('+')) {
      // Asumimos México +52 si son 10 dígitos
      if (phone.length == 10) {
        phone = '+52$phone';
      } else {
        phone = '+$phone';
      }
    }
    return phone;
  }

  Future<void> _addContact() async {
    if (!_formKey.currentState!.validate()) return;

    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    final rawPhone = _phoneCtrl.text.trim();
    final rawEmail = _emailCtrl.text.trim();

    if (rawPhone.isEmpty && rawEmail.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ingresa un teléfono o un correo para buscar.'),
        ),
      );
      return;
    }

    setState(() => _adding = true);

    try {
      Query<Map<String, dynamic>> query =
          _firestore.collection('users') as Query<Map<String, dynamic>>;

      if (rawPhone.isNotEmpty) {
        final phone = _normalizePhone(rawPhone);
        query = query.where('phoneNumber', isEqualTo: phone);
      } else {
        query = query.where('emailTec', isEqualTo: rawEmail);
      }

      final snap = await query.limit(1).get();

      if (snap.docs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se encontró ningún usuario.')),
        );
        return;
      }

      final userDoc = snap.docs.first;
      final foundUid = userDoc.id;

      if (foundUid == currentUser.uid) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No puedes agregarte a ti mismo.')),
        );
        return;
      }

      // Verificar si ya existe contacto
      final existing = await _firestore
          .collection('contacts')
          .where('ownerId', isEqualTo: currentUser.uid)
          .where('contactId', isEqualTo: foundUid)
          .limit(1)
          .get();

      if (existing.docs.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Este contacto ya está en tu lista.')),
        );
        return;
      }

      await _firestore.collection('contacts').add({
        'ownerId': currentUser.uid,
        'contactId': foundUid,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Contacto agregado correctamente.')),
      );

      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al agregar contacto: $e')));
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Agregar contacto')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              const Text(
                'Puedes agregar un contacto usando su número de teléfono '
                'registrado o su correo institucional.',
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Número de teléfono',
                  hintText: '+52 1 555 555 5555 o 10 dígitos',
                ),
              ),
              const SizedBox(height: 8),
              const Center(child: Text('o')),
              const SizedBox(height: 8),
              TextFormField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Correo institucional',
                  hintText: 'usuario@itcelaya.edu.mx',
                ),
                validator: (value) {
                  final v = value?.trim() ?? '';
                  final p = _phoneCtrl.text.trim();
                  if (v.isEmpty && p.isEmpty) {
                    return 'Ingresa al menos teléfono o correo.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _adding ? null : _addContact,
                  icon: _adding
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check),
                  label: Text(_adding ? 'Agregando...' : 'Buscar y agregar'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
