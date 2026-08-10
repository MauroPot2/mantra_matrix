import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:mantra_matrix/features/auth/domain/repositories/auth_repository.dart';

class FirebaseAuthRepository implements AuthRepository {
  final FirebaseAuth _firebaseAuth;
  final FirebaseFirestore _firestore;
  final GoogleSignIn _googleSignIn;

  bool _googleInitialized = false;

  FirebaseAuthRepository(
    this._firebaseAuth,
    this._firestore, {
    GoogleSignIn? googleSignIn,
  }) : _googleSignIn = googleSignIn ?? GoogleSignIn.instance;

  @override
  User? get currentUser => _firebaseAuth.currentUser;

  @override
  Stream<User?> authStateChanges() => _firebaseAuth.authStateChanges();

  Future<void> _ensureGoogleInitialized() async {
    if (_googleInitialized) return;
    await _googleSignIn.initialize();
    _googleInitialized = true;
  }

  @override
  Future<UserCredential> signInWithGoogle() async {
    try {
      await _ensureGoogleInitialized();

      if (!_googleSignIn.supportsAuthenticate()) {
        throw const AuthOperationException(
          'Google Sign-In non è disponibile su questa piattaforma.',
        );
      }

      final googleUser = await _googleSignIn.authenticate();
      final googleAuth = googleUser.authentication;
      final idToken = googleAuth.idToken;

      if (idToken == null || idToken.isEmpty) {
        throw const AuthOperationException(
          'Google non ha restituito un token di autenticazione valido.',
        );
      }

      final credential = GoogleAuthProvider.credential(idToken: idToken);
      final userCredential = await _firebaseAuth.signInWithCredential(
        credential,
      );

      await _saveProfileAfterAuthentication(userCredential);
      return userCredential;
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) {
        throw const AuthCancelledException();
      }

      throw AuthOperationException(_googleErrorMessage(error), cause: error);
    } on FirebaseAuthException catch (error) {
      throw AuthOperationException(_firebaseErrorMessage(error), cause: error);
    } on AuthCancelledException {
      rethrow;
    } on AuthOperationException {
      rethrow;
    } catch (error) {
      throw AuthOperationException(
        'Accesso con Google non riuscito: $error',
        cause: error,
      );
    }
  }

  @override
  Future<UserCredential> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    try {
      final userCredential = await _firebaseAuth.signInWithEmailAndPassword(
        email: _normalizeEmail(email),
        password: password,
      );

      await _saveProfileAfterAuthentication(userCredential);
      return userCredential;
    } on FirebaseAuthException catch (error) {
      throw AuthOperationException(_firebaseErrorMessage(error), cause: error);
    } catch (error) {
      throw AuthOperationException(
        'Accesso con email non riuscito: $error',
        cause: error,
      );
    }
  }

  @override
  Future<UserCredential> registerWithEmailAndPassword({
    required String displayName,
    required String email,
    required String password,
  }) async {
    try {
      final userCredential = await _firebaseAuth.createUserWithEmailAndPassword(
        email: _normalizeEmail(email),
        password: password,
      );

      final trimmedName = displayName.trim();
      final createdUser = userCredential.user;
      if (createdUser != null && trimmedName.isNotEmpty) {
        await createdUser.updateDisplayName(trimmedName);
        await createdUser.reload();
      }

      final refreshedCredentialUser = _firebaseAuth.currentUser;
      if (refreshedCredentialUser != null) {
        try {
          await _saveUserProfile(refreshedCredentialUser, isNewUser: true);
        } on FirebaseException {
          // La registrazione Auth è già riuscita. Il profilo verrà
          // riallineato al prossimo accesso se Firestore non è disponibile.
        }
      }

      return userCredential;
    } on FirebaseAuthException catch (error) {
      throw AuthOperationException(_firebaseErrorMessage(error), cause: error);
    } catch (error) {
      throw AuthOperationException(
        'Registrazione non riuscita: $error',
        cause: error,
      );
    }
  }

  @override
  Future<void> sendPasswordResetEmail({required String email}) async {
    try {
      await _firebaseAuth.setLanguageCode('it');
      await _firebaseAuth.sendPasswordResetEmail(email: _normalizeEmail(email));
    } on FirebaseAuthException catch (error) {
      // Non riveliamo se l'indirizzo esiste. Manteniamo però gli errori che
      // indicano un problema reale di configurazione, formato o connettività.
      if (error.code == 'user-not-found') return;

      throw AuthOperationException(_firebaseErrorMessage(error), cause: error);
    } catch (error) {
      throw AuthOperationException(
        'Invio dell’email di recupero non riuscito: $error',
        cause: error,
      );
    }
  }

  Future<void> _saveProfileAfterAuthentication(
    UserCredential userCredential,
  ) async {
    final user = userCredential.user;
    if (user == null) return;

    try {
      await _saveUserProfile(
        user,
        isNewUser: userCredential.additionalUserInfo?.isNewUser ?? false,
      );
    } on FirebaseException {
      // Il profilo Firestore è accessorio: un problema di regole o rete non
      // deve invalidare una sessione Firebase Auth già riuscita.
    }
  }

  Future<void> _saveUserProfile(User user, {required bool isNewUser}) {
    final data = <String, dynamic>{
      'uid': user.uid,
      'display_name': user.displayName,
      'email': user.email,
      'photo_url': user.photoURL,
      'provider_ids': user.providerData
          .map((provider) => provider.providerId)
          .toSet()
          .toList(growable: false),
      'last_login_at': FieldValue.serverTimestamp(),
    };

    if (isNewUser) {
      data['created_at'] = FieldValue.serverTimestamp();
    }

    return _firestore
        .collection('users')
        .doc(user.uid)
        .set(data, SetOptions(merge: true));
  }

  @override
  Future<void> signOut() async {
    Object? firebaseError;

    try {
      await _firebaseAuth.signOut();
    } catch (error) {
      firebaseError = error;
    }

    try {
      await _ensureGoogleInitialized();
      await _googleSignIn.signOut();
    } catch (error) {
      if (firebaseError == null) {
        throw AuthOperationException(
          'Disconnessione Google non riuscita: $error',
          cause: error,
        );
      }
    }

    if (firebaseError != null) {
      throw AuthOperationException(
        'Disconnessione Firebase non riuscita: $firebaseError',
        cause: firebaseError,
      );
    }
  }

  static String _normalizeEmail(String email) => email.trim().toLowerCase();

  static String _googleErrorMessage(GoogleSignInException error) {
    return switch (error.code) {
      GoogleSignInExceptionCode.canceled => 'Accesso annullato.',
      GoogleSignInExceptionCode.clientConfigurationError =>
        'Configurazione Google non valida. Controlla package name, SHA e google-services.json.',
      GoogleSignInExceptionCode.uiUnavailable =>
        'La schermata Google Sign-In non è disponibile sul dispositivo.',
      _ =>
        error.description == null || error.description!.trim().isEmpty
            ? 'Google Sign-In non riuscito (${error.code.name}).'
            : error.description!,
    };
  }

  static String _firebaseErrorMessage(FirebaseAuthException error) {
    return switch (error.code) {
      'account-exists-with-different-credential' =>
        'Esiste già un account con la stessa email ma con un metodo di accesso diverso.',
      'email-already-in-use' =>
        'Esiste già un account registrato con questa email.',
      'invalid-email' => 'Inserisci un indirizzo email valido.',
      'invalid-credential' ||
      'wrong-password' ||
      'user-not-found' => 'Email o password non corretti.',
      'weak-password' => 'La password è troppo debole. Usa almeno 8 caratteri.',
      'missing-password' => 'Inserisci la password.',
      'operation-not-allowed' =>
        'Questo metodo di accesso non è abilitato nella Console Firebase.',
      'user-disabled' => 'Questo account è stato disabilitato.',
      'too-many-requests' =>
        'Troppi tentativi. Attendi qualche minuto e riprova.',
      'network-request-failed' =>
        'Connessione assente o instabile. Controlla la rete e riprova.',
      _ => error.message ?? 'Autenticazione Firebase non riuscita.',
    };
  }
}
