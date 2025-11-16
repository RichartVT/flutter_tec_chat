class AppUser {
  final String uid;
  final String? phoneNumber;
  final String? emailTec;
  final String? displayName;
  final String? avatarUrl;
  final String about;
  final String role;

  AppUser({
    required this.uid,
    this.phoneNumber,
    this.emailTec,
    this.displayName,
    this.avatarUrl,
    this.about = 'Disponible',
    this.role = 'alumno',
  });

  factory AppUser.fromMap(Map<String, dynamic> map, String uid) {
    return AppUser(
      uid: uid,
      phoneNumber: map['phoneNumber'] as String?,
      emailTec: map['emailTec'] as String?,
      displayName: map['displayName'] as String?,
      avatarUrl: map['avatarUrl'] as String?,
      about: (map['about'] as String?) ?? 'Disponible',
      role: (map['role'] as String?) ?? 'alumno',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'phoneNumber': phoneNumber,
      'emailTec': emailTec,
      'displayName': displayName,
      'avatarUrl': avatarUrl,
      'about': about,
      'role': role,
    };
  }
}
