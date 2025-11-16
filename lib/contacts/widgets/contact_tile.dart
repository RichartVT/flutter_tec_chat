import 'package:flutter/material.dart';

import '../models/app_user_contact.dart';

class ContactTile extends StatelessWidget {
  final AppUserContact user;

  const ContactTile({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        backgroundImage: user.avatarUrl != null
            ? NetworkImage(user.avatarUrl!)
            : null,
        child: user.avatarUrl == null
            ? Text(
                user.displayName.isNotEmpty
                    ? user.displayName.characters.first.toUpperCase()
                    : '?',
              )
            : null,
      ),
      title: Text(user.displayName),
      subtitle: Text(user.emailTec ?? user.phoneNumber ?? ''),
      onTap: () {
        // Aquí después puedes iniciar un nuevo chat con este contacto.
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Aquí iniciarías chat con ${user.displayName}'),
          ),
        );
      },
    );
  }
}
