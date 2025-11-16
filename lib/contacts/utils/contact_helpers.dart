import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/app_user_contact.dart';

Future<AppUserContact?> loadContactUser(String uid) async {
  final doc = await FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .get();

  if (!doc.exists) return null;
  final data = doc.data() ?? {};

  final displayName =
      (data['displayName'] as String?) ??
      (data['emailTec'] as String?) ??
      (data['phoneNumber'] as String?) ??
      'Contacto';

  return AppUserContact(
    uid: uid,
    displayName: displayName,
    emailTec: data['emailTec'] as String?,
    phoneNumber: data['phoneNumber'] as String?,
    avatarUrl: data['avatarUrl'] as String?,
  );
}
