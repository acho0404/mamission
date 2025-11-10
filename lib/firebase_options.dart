import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return const FirebaseOptions(
        apiKey: "AIzaSyAnoaHTnsBnt2i3wSlDTmgW_mow3n1zHuQ",
        appId: "1:896613141389:android:91c1665dba582f7667cbc4",
        messagingSenderId: "896613141389",
        projectId: "mamission-1b54a",
        storageBucket: "mamission-1b54a.firebasestorage.app",
      );
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return const FirebaseOptions(
          apiKey: "AIzaSyAnoaHTnsBnt2i3wSlDTmgW_mow3n1zHuQ",
          appId: "1:896613141389:android:91c1665dba582f7667cbc4",
          messagingSenderId: "896613141389",
          projectId: "mamission-1b54a",
          storageBucket: "mamission-1b54a.firebasestorage.app",
        );

      case TargetPlatform.iOS:
        return const FirebaseOptions(
          apiKey: "AIzaSyAnoaHTnsBnt2i3wSlDTmgW_mow3n1zHuQ",
          appId: "1:896613141389:android:91c1665dba582f7667cbc4",
          messagingSenderId: "896613141389",
          projectId: "mamission-1b54a",
          storageBucket: "mamission-1b54a.firebasestorage.app",
          iosClientId: "",
          iosBundleId: "com.mamission.app",
        );

      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions ne supporte pas cette plateforme',
        );
    }
  }
}
