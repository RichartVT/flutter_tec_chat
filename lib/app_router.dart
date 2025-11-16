// app_router.dart
import 'package:flutter/material.dart';

import 'screens/auth/phone_auth_screen.dart';
import 'features/chats/presentation/screens/chats_list_screen.dart';

class AppRouter {
  static const String initialRoute = '/phone-auth';

  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case '/phone-auth':
        return MaterialPageRoute(builder: (_) => const PhoneAuthScreen());
      case '/home':
        return MaterialPageRoute(builder: (_) => const ChatsListScreen());
      default:
        return MaterialPageRoute(builder: (_) => const PhoneAuthScreen());
    }
  }
}
