/// Every user-facing string on the face-capture screen (check-in / check-out).
///
/// The app is otherwise English-only, so this is deliberately not a full
/// localisation framework: two const instances, picked by
/// `AppSettingsService.faceCaptureStrings`. [english] is also the default
/// argument of the shared helpers (`FaceGuidePlacement.issue` and the
/// `FaceRecognitionService` instruction builders), which keeps the
/// face-registration screen on English without being touched.
abstract class FaceCaptureStrings {
  const FaceCaptureStrings();

  static const FaceCaptureStrings english = _EnglishStrings();
  static const FaceCaptureStrings bangla = _BanglaStrings();

  // App bar and section headings.
  String get appBarCheckIn;
  String get appBarCheckOut;
  String get livenessChallenges;
  String get identityVerified;
  String get locationCaptured;
  String get capturingLocation;

  // Coaching and status lines.
  String get initializing;
  String get positionFaceInGuide;
  String get faceDataMissing;
  String get cameraPermissionDenied;
  String get cameraStreamFailed;
  String get cameraFormatUnsupported;
  String get onlyOneFace;
  String get lookStraightAtCamera;
  String get lookStraightThenSmile;
  String get holdThatSmile;
  String get smile;
  String get openEyesAndLook;
  String get nowBlink;
  String get openEyesAgain;
  String get blinkDetected;
  String get turnSlightlyLeft;
  String get turnSlightlyRight;
  String get holdStill;
  String get holdSteady;
  String get fillTheFaceGuide;
  String get checkingIdentity;
  String get checkingAdditionalSteps;
  String get identityVerifiedEarly;
  String get verifyingIdentity;
  String get verificationCameraBusy;
  String get successCheckIn;
  String get successCheckOut;

  // Placement guidance shared with `FaceGuidePlacement`.
  String get holdStillWhileFocusing;
  String get moveCloser;
  String get moveBack;
  String get centerFace;

  // Challenge names shown in the liveness list.
  String get angleStraight;
  String get angleLeft;
  String get angleRight;
  String get angleUp;
  String get angleDown;
  String get angleUnknown;

  // Instruction lines for the same challenges.
  String get instructStraight;
  String get instructLeft;
  String get instructRight;
  String get instructUp;
  String get instructDown;
  String get instructUnknown;

  String get challengeStraight;
  String get challengeSmile;
  String get challengeBlink;
  String get challengeLeft;
  String get challengeRight;

  // Primary button labels.
  String get buttonInitializing;
  String get buttonScanning;
  String get buttonVerifying;
  String get buttonCapturingLocation;
  String get buttonDone;
  String get buttonRegisterFace;
  String get buttonRetry;

  // Messages that carry a runtime value.
  String cameraInitFailed(Object error);
  String verificationFailed(Object error);
  String matchPercent(String value);

  // Face registration screen. It shares the capture stage with check-in, so the
  // two stay in one place: a toggle that covered only one of them would leave
  // the re-register flow in English.
  String get registrationTitle;
  String get initializingCamera;
  String get positionFaceInGuideEllipsis;
  String get cameraPermissionDeniedShort;
  String get registrationFormatUnsupported;
  String get positionFaceInFrame;
  String get capturingNow;
  String get lowerChin;
  String get captureFailed;
  String get registrationComplete;
  String get registrationLocalOnly;
  String get differentPersonDetected;
  String get differentPersonTitle;
  String get differentPersonBody;
  String get okRetry;
  String get doneExclaim;
  String get registrationCompleteTitle;
  String get registrationProgress;
  String get tipsTitle;
  String get tipLighting;
  String get tipFollowAngles;
  String get tipHoldSteady;
  String get tipEyesOpen;
  String get tipOnlyFace;
  String get doneWithTick;

  String cameraError(Object error);
  String stepOf(int current, int total);

  /// Families that actually carry Bengali glyphs.
  ///
  /// The capture screens set Poppins for the Latin copy; Poppins has no Bengali
  /// coverage, so these are offered as the fallback chain behind it.
  List<String> get fontFamilyFallback;
}

class _EnglishStrings extends FaceCaptureStrings {
  const _EnglishStrings();

  @override
  String get appBarCheckIn => 'Check In';
  @override
  String get appBarCheckOut => 'Check Out';
  @override
  String get livenessChallenges => 'Liveness challenges';
  @override
  String get identityVerified => 'Identity Verified';
  @override
  String get locationCaptured => 'Location Captured';
  @override
  String get capturingLocation => 'Capturing Location...';

  @override
  String get initializing => 'Initializing...';
  @override
  String get positionFaceInGuide => 'Position your face in the guide';
  @override
  String get faceDataMissing =>
      'Your face data is missing or unreadable. Please register your face again.';
  @override
  String get cameraPermissionDenied => 'Camera permission denied.';
  @override
  String get cameraStreamFailed =>
      'Camera stream failed. Close other camera apps and retry.';
  @override
  String get cameraFormatUnsupported =>
      'Camera format not supported — close and reopen check-in';
  @override
  String get onlyOneFace => 'Only one face should be visible';
  @override
  String get lookStraightAtCamera => 'Look straight at the camera';
  @override
  String get lookStraightThenSmile => 'Look straight, then smile';
  @override
  String get holdThatSmile => 'Hold that smile...';
  @override
  String get smile => 'Smile! 😄';
  @override
  String get openEyesAndLook => 'Open your eyes and look at camera';
  @override
  String get nowBlink => 'Now blink your eyes';
  @override
  String get openEyesAgain => 'Open your eyes again';
  @override
  String get blinkDetected => 'Blink detected ✓';
  @override
  String get turnSlightlyLeft => 'Turn your face slightly left';
  @override
  String get turnSlightlyRight => 'Turn your face slightly right';
  @override
  String get holdStill => 'Hold still while the camera focuses';
  @override
  String get holdSteady => 'Hold steady...';
  @override
  String get fillTheFaceGuide => 'Fill the face guide';
  @override
  String get checkingIdentity => 'Checking identity...';
  @override
  String get checkingAdditionalSteps =>
      'Checking if additional steps are needed...';
  @override
  String get identityVerifiedEarly =>
      'Identity verified early — additional challenge steps not required.';
  @override
  String get verifyingIdentity => 'Verifying identity...';
  @override
  String get verificationCameraBusy =>
      'Verification failed: camera is busy. Please tap Retry.';
  @override
  String get successCheckIn => 'Check-in request submitted!';
  @override
  String get successCheckOut => 'Check-out request submitted!';

  @override
  String get holdStillWhileFocusing => 'Hold still while the camera focuses';
  @override
  String get moveCloser => 'Move closer and fill the face guide';
  @override
  String get moveBack => 'Move back a little — your face is too close';
  @override
  String get centerFace => 'Center your face inside the guide';

  @override
  String get angleStraight => 'Look Straight';
  @override
  String get angleLeft => 'Turn Left';
  @override
  String get angleRight => 'Turn Right';
  @override
  String get angleUp => 'Look Up';
  @override
  String get angleDown => 'Look Down';
  @override
  String get angleUnknown => 'Adjust Position';

  @override
  String get instructStraight => 'Look straight at the camera';
  @override
  String get instructLeft => 'Slowly turn your face to the left';
  @override
  String get instructRight => 'Slowly turn your face to the right';
  @override
  String get instructUp => 'Slightly tilt your head upward';
  @override
  String get instructDown => 'Slightly tilt your head downward';
  @override
  String get instructUnknown => 'Position your face in the guide';

  @override
  String get challengeStraight => 'Look straight at the camera';
  @override
  String get challengeSmile => 'Smile! 😄';
  @override
  String get challengeBlink => 'Blink your eyes';
  @override
  String get challengeLeft => 'Turn your face slightly left';
  @override
  String get challengeRight => 'Turn your face slightly right';

  @override
  String get buttonInitializing => 'Initializing…';
  @override
  String get buttonScanning => 'Scanning face…';
  @override
  String get buttonVerifying => 'Verifying…';
  @override
  String get buttonCapturingLocation => 'Capturing location…';
  @override
  String get buttonDone => 'Done';
  @override
  String get buttonRegisterFace => 'Register face';
  @override
  String get buttonRetry => 'Retry';

  @override
  String cameraInitFailed(Object error) => 'Camera initialization failed: $error';
  @override
  String verificationFailed(Object error) => 'Verification failed: $error';
  @override
  String matchPercent(String value) => '$value% match';

  @override
  String get registrationTitle => 'Face Registration';
  @override
  String get initializingCamera => 'Initializing camera...';
  @override
  String get positionFaceInGuideEllipsis => 'Position your face in the guide…';
  @override
  String get cameraPermissionDeniedShort => 'Camera permission denied';
  @override
  String get registrationFormatUnsupported =>
      'Camera format not supported — close and reopen this screen';
  @override
  String get positionFaceInFrame => 'Position your face in the frame';
  @override
  String get capturingNow => 'Capturing...';
  @override
  String get lowerChin => 'Lower your chin slightly and keep eyes visible';
  @override
  String get captureFailed => 'Capture failed. Try again.';
  @override
  String get registrationComplete => 'Registration complete!';
  @override
  String get registrationLocalOnly =>
      'Face saved locally for this session, but backend sync failed.';
  @override
  String get differentPersonDetected => 'Different person detected! Try again.';
  @override
  String get differentPersonTitle => 'Different Person!';
  @override
  String get differentPersonBody =>
      'The captured face does not match the previous captures. '
      'All registration photos must be of the same person.';
  @override
  String get okRetry => "OK, I'll retry";
  @override
  String get doneExclaim => 'Done!';
  @override
  String get registrationCompleteTitle => 'Registration Complete!';
  @override
  String get registrationProgress => 'Registration Progress';
  @override
  String get tipsTitle => 'Tips';
  @override
  String get tipLighting => 'Ensure good, even lighting on your face';
  @override
  String get tipFollowAngles => 'Follow the angle instructions carefully';
  @override
  String get tipHoldSteady => 'Hold each position steady for about 1 second';
  @override
  String get tipEyesOpen => 'Keep both eyes open during captures';
  @override
  String get tipOnlyFace => 'Only your face should be visible in the frame';
  @override
  String get doneWithTick => 'Done ✓';

  @override
  String cameraError(Object error) => 'Camera error: $error';
  @override
  String stepOf(int current, int total) => 'Step $current of $total';

  @override
  List<String> get fontFamilyFallback => const [];
}

class _BanglaStrings extends FaceCaptureStrings {
  const _BanglaStrings();

  @override
  String get appBarCheckIn => 'চেক ইন';
  @override
  String get appBarCheckOut => 'চেক আউট';
  @override
  String get livenessChallenges => 'লাইভনেস ধাপ';
  @override
  String get identityVerified => 'পরিচয় যাচাই সম্পন্ন';
  @override
  String get locationCaptured => 'লোকেশন নেওয়া হয়েছে';
  @override
  String get capturingLocation => 'লোকেশন নেওয়া হচ্ছে...';

  @override
  String get initializing => 'প্রস্তুত হচ্ছে...';
  @override
  String get positionFaceInGuide => 'আপনার মুখ গাইডের ভিতরে রাখুন';
  @override
  String get faceDataMissing =>
      'আপনার মুখের ডেটা পাওয়া যাচ্ছে না বা পড়া যাচ্ছে না। অনুগ্রহ করে আবার মুখ রেজিস্ট্রেশন করুন।';
  @override
  String get cameraPermissionDenied => 'ক্যামেরার অনুমতি দেওয়া হয়নি।';
  @override
  String get cameraStreamFailed =>
      'ক্যামেরা চালু হয়েছে না। অন্য ক্যামেরা অ্যাপ বন্ধ করে আবার চেষ্টা করুন।';
  @override
  String get cameraFormatUnsupported =>
      'ক্যামেরা ফরম্যাট সমর্থিত নয় — চেক-ইন বন্ধ করে আবার খুলুন';
  @override
  String get onlyOneFace => 'একসাথে শুধু একটি মুখ দেখা যাবে';
  @override
  String get lookStraightAtCamera => 'সোজা ক্যামেরার দিকে তাকান';
  @override
  String get lookStraightThenSmile => 'সোজা তাকান, তারপর হাসুন';
  @override
  String get holdThatSmile => 'হাসিটা ধরে রাখুন...';
  @override
  String get smile => 'হাসুন! 😄';
  @override
  String get openEyesAndLook => 'চোখ খুলে ক্যামেরার দিকে তাকান';
  @override
  String get nowBlink => 'এখন চোখের পলক ফেলুন';
  @override
  String get openEyesAgain => 'আবার চোখ খুলুন';
  @override
  String get blinkDetected => 'পলক শনাক্ত হয়েছে ✓';
  @override
  String get turnSlightlyLeft => 'মুখ সামান্য বাঁ দিকে ঘোরান';
  @override
  String get turnSlightlyRight => 'মুখ সামান্য ডান দিকে ঘোরান';
  @override
  String get holdStill => 'ক্যামেরা ফোকাস হওয়া পর্যন্ত স্থির থাকুন';
  @override
  String get holdSteady => 'স্থির থাকুন...';
  @override
  String get fillTheFaceGuide => 'মুখ দিয়ে গাইডটি পূর্ণ করুন';
  @override
  String get checkingIdentity => 'পরিচয় যাচাই করা হচ্ছে...';
  @override
  String get checkingAdditionalSteps => 'অতিরিক্ত ধাপ দরকার কি না দেখা হচ্ছে...';
  @override
  String get identityVerifiedEarly =>
      'পরিচয় আগেই যাচাই হয়েছে — অতিরিক্ত ধাপের দরকার নেই।';
  @override
  String get verifyingIdentity => 'পরিচয় যাচাই চলছে...';
  @override
  String get verificationCameraBusy =>
      'যাচাই ব্যর্থ: ক্যামেরা ব্যস্ত। অনুগ্রহ করে রিট্রাই চাপুন।';
  @override
  String get successCheckIn => 'চেক-ইন অনুরোধ জমা হয়েছে!';
  @override
  String get successCheckOut => 'চেক-আউট অনুরোধ জমা হয়েছে!';

  @override
  String get holdStillWhileFocusing => 'ক্যামেরা ফোকাস হওয়া পর্যন্ত স্থির থাকুন';
  @override
  String get moveCloser => 'আরও কাছে আসুন এবং গাইডটি পূর্ণ করুন';
  @override
  String get moveBack => 'একটু পিছিয়ে যান — মুখ খুব কাছে';
  @override
  String get centerFace => 'মুখ গাইডের মাঝখানে রাখুন';

  @override
  String get angleStraight => 'সোজা তাকান';
  @override
  String get angleLeft => 'বাঁ দিকে ঘোরান';
  @override
  String get angleRight => 'ডান দিকে ঘোরান';
  @override
  String get angleUp => 'উপরে তাকান';
  @override
  String get angleDown => 'নিচে তাকান';
  @override
  String get angleUnknown => 'অবস্থান ঠিক করুন';

  @override
  String get instructStraight => 'সোজা ক্যামেরার দিকে তাকান';
  @override
  String get instructLeft => 'ধীরে মুখ বাঁ দিকে ঘোরান';
  @override
  String get instructRight => 'ধীরে মুখ ডান দিকে ঘোরান';
  @override
  String get instructUp => 'মাথা সামান্য উপরে হেলান';
  @override
  String get instructDown => 'মাথা সামান্য নিচে হেলান';
  @override
  String get instructUnknown => 'আপনার মুখ গাইডের ভিতরে রাখুন';

  @override
  String get challengeStraight => 'সোজা ক্যামেরার দিকে তাকান';
  @override
  String get challengeSmile => 'হাসুন! 😄';
  @override
  String get challengeBlink => 'চোখের পলক ফেলুন';
  @override
  String get challengeLeft => 'মুখ সামান্য বাঁ দিকে ঘোরান';
  @override
  String get challengeRight => 'মুখ সামান্য ডান দিকে ঘোরান';

  @override
  String get buttonInitializing => 'প্রস্তুত হচ্ছে…';
  @override
  String get buttonScanning => 'মুখ স্ক্যান হচ্ছে…';
  @override
  String get buttonVerifying => 'যাচাই হচ্ছে…';
  @override
  String get buttonCapturingLocation => 'লোকেশন নেওয়া হচ্ছে…';
  @override
  String get buttonDone => 'সম্পন্ন';
  @override
  String get buttonRegisterFace => 'মুখ রেজিস্টার করুন';
  @override
  String get buttonRetry => 'আবার চেষ্টা করুন';

  @override
  String cameraInitFailed(Object error) => 'ক্যামেরা চালু করা যায়নি: $error';
  @override
  String verificationFailed(Object error) => 'যাচাই ব্যর্থ: $error';
  @override
  String matchPercent(String value) => 'মিল $value%';

  @override
  String get registrationTitle => 'মুখ রেজিস্ট্রেশন';
  @override
  String get initializingCamera => 'ক্যামেরা চালু হচ্ছে...';
  @override
  String get positionFaceInGuideEllipsis => 'আপনার মুখ গাইডের ভিতরে রাখুন…';
  @override
  String get cameraPermissionDeniedShort => 'ক্যামেরার অনুমতি দেওয়া হয়নি';
  @override
  String get registrationFormatUnsupported =>
      'ক্যামেরা ফরম্যাট সমর্থিত নয় — এই স্ক্রিনটি বন্ধ করে আবার খুলুন';
  @override
  String get positionFaceInFrame => 'আপনার মুখ ফ্রেমের ভিতরে রাখুন';
  @override
  String get capturingNow => 'ছবি নেওয়া হচ্ছে...';
  @override
  String get lowerChin => 'চিবুক সামান্য নিচু করুন এবং চোখ দৃশ্যমান রাখুন';
  @override
  String get captureFailed => 'ছবি নেওয়া যায়নি। আবার চেষ্টা করুন।';
  @override
  String get registrationComplete => 'রেজিস্ট্রেশন সম্পন্ন!';
  @override
  String get registrationLocalOnly =>
      'মুখ শুধু এই সেশনের জন্য সেভ হয়েছে, সার্ভারে পাঠানো যায়নি।';
  @override
  String get differentPersonDetected => 'অন্য ব্যক্তি শনাক্ত হয়েছে! আবার চেষ্টা করুন।';
  @override
  String get differentPersonTitle => 'অন্য ব্যক্তি!';
  @override
  String get differentPersonBody =>
      'নেওয়া ছবিটি আগের ছবিগুলোর সাথে মিলছে না। '
      'রেজিস্ট্রেশনের সব ছবি একই ব্যক্তির হতে হবে।';
  @override
  String get okRetry => 'ঠিক আছে, আবার চেষ্টা করব';
  @override
  String get doneExclaim => 'সম্পন্ন!';
  @override
  String get registrationCompleteTitle => 'রেজিস্ট্রেশন সম্পন্ন!';
  @override
  String get registrationProgress => 'রেজিস্ট্রেশন অগ্রগতি';
  @override
  String get tipsTitle => 'পরামর্শ';
  @override
  String get tipLighting => 'মুখে সমান আলো আছে কি না দেখুন';
  @override
  String get tipFollowAngles => 'প্রতিটি কোণের নির্দেশনা মনোযোগ দিয়ে মানুন';
  @override
  String get tipHoldSteady => 'প্রতিটি অবস্থানে প্রায় ১ সেকেন্ড স্থির থাকুন';
  @override
  String get tipEyesOpen => 'ছবি নেওয়ার সময় দুই চোখ খোলা রাখুন';
  @override
  String get tipOnlyFace => 'ফ্রেমে শুধু আপনার মুখ থাকবে';
  @override
  String get doneWithTick => 'সম্পন্ন ✓';

  @override
  String cameraError(Object error) => 'ক্যামেরা ত্রুটি: $error';
  @override
  String stepOf(int current, int total) => 'ধাপ $current / $total';

  @override
  List<String> get fontFamilyFallback =>
      const ['Noto Sans Bengali', 'Noto Sans Bengali UI', 'Bangla'];
}
