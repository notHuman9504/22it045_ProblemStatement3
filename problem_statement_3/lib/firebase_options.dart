import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with your Firebase apps.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for android - '
          'you can create a temporary placeholder using the Firebase Console.',
        );
      case TargetPlatform.iOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for ios - '
          'you can create a temporary placeholder using the Firebase Console.',
        );
      case TargetPlatform.macOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for macos - '
          'you can create a temporary placeholder using the Firebase Console.',
        );
      case TargetPlatform.windows:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for windows - '
          'you can create a temporary placeholder using the Firebase Console.',
        );
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can create a temporary placeholder using the Firebase Console.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  // Replace these values with your actual Firebase configuration from the Firebase Console
  static const FirebaseOptions web = FirebaseOptions(
  apiKey: "AIzaSyAY0Ed2bmHFXt8u0QGyrgoS6hM6iLbxhyI",
  authDomain: "todo-app-ce175.firebaseapp.com",
  projectId: "todo-app-ce175",
  storageBucket: "todo-app-ce175.firebasestorage.app",
  messagingSenderId: "628159934799",
  appId: "1:628159934799:web:968b41dabfd01ac130553a",
  measurementId: "G-G96BCKWRKC"
  );
} 