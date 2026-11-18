# Tec Chat

A real-time messaging app built with Flutter and Firebase: phone-number sign-in, contacts, one-to-one chats, group chats and image/GIF messages that update live across devices.

> Part of my portfolio: [richart.dev](https://www.richart.dev)

## Features

- **Phone authentication** with SMS verification (Firebase Auth).
- **Contacts**: add people by phone number and start a conversation from your list.
- **Real-time chats**: messages appear instantly through Firestore streams, ordered by server timestamp.
- **Group chats**: create a group, pick its members and chat with everyone at once.
- **Images and GIFs** in conversations, picked from the device.
- **Chat list** with each conversation's latest message.
- **Profile** screen for the signed-in user.
- Runs on **Android, iOS and the web**.

## Tech stack

- **App:** Flutter (Dart)
- **Firebase:** Authentication (phone) and Cloud Firestore
- **Media:** `file_picker`, `image_picker`

## Data model

```
users/{uid}
  contacts/{contactId}
chats/{chatId}            # isGroup, members[], lastMessage, timestamps
  messages/{messageId}    # type: text | image | gif, sender, createdAt
```

A chat is a single document whether it has two members or twenty, so one-to-one and group conversations share the same screens and queries.

## Project structure

```
lib/
  app_router.dart                  # named routes (/phone-auth, /home)
  core/                            # theme and shared widgets
  data/                            # models and auth service
  contacts/                        # contact list, add contact
  features/
    auth/                          # phone sign-in
    chats/                         # chat list, chat detail, create group
    profile/
  main.dart
```

## Getting started

**Requirements:** Flutter SDK and a Firebase project.

```bash
git clone https://github.com/RichartVT/flutter_tec_chat.git
cd flutter_tec_chat
flutter pub get
```

1. In Firebase, enable **Phone** authentication and create a Firestore database.
2. Generate your own config (it is not committed to the repo):

   ```bash
   dart pub global activate flutterfire_cli
   flutterfire configure
   ```

3. Run it:

   ```bash
   flutter run              # mobile
   flutter run -d chrome    # web
   ```

For local testing, add test phone numbers under *Authentication → Sign-in method → Phone* so you don't need real SMS codes.

## Next steps

- Move image messages to Firebase Storage. They are currently stored inline in Firestore, which keeps the prototype simple but limits image size.
- Read receipts and typing indicators.
- Push notifications for new messages.

## What I learned

Modelling chats so that direct and group conversations share one structure kept the code small, and building on Firestore streams instead of polling made real-time updates almost free. Keeping Firebase credentials out of version control — and cleaning them from the history after an early mistake — was also a lesson I won't forget.

## Author

**Richart Vázquez de la Torre** — [richart.dev](https://www.richart.dev) · [GitHub](https://github.com/RichartVT)
