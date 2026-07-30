import 'package:firebase_auth/firebase_auth.dart';

abstract class AuthRepository {
  User? get currentUser;

  Stream<User?> authStateChanges();

  Future<UserCredential> signInWithGoogle();

  Future<UserCredential> signInWithEmailAndPassword({
    required String email,
    required String password,
  });

  Future<UserCredential> registerWithEmailAndPassword({
    required String displayName,
    required String email,
    required String password,
  });

  Future<void> sendPasswordResetEmail({required String email});

  Future<void> signOut();
}

class AuthCancelledException implements Exception {
  const AuthCancelledException();

  @override
  String toString() => 'Accesso annullato.';
}

class AuthOperationException implements Exception {
  final String message;
  final Object? cause;

  const AuthOperationException(this.message, {this.cause});

  @override
  String toString() => message;
}
