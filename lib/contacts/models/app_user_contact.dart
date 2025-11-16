class AppUserContact {
  final String uid;
  final String displayName;
  final String? emailTec;
  final String? phoneNumber;
  final String? avatarUrl;

  AppUserContact({
    required this.uid,
    required this.displayName,
    this.emailTec,
    this.phoneNumber,
    this.avatarUrl,
  });
}
