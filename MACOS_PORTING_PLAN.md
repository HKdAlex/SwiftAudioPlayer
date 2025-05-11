# SwiftAudioPlayer macOS Porting Plan

This document outlines the step-by-step plan to adapt the SwiftAudioPlayer package for compatibility with macOS. It will be updated iteratively as progress is made.

## Legend

- ⏳ **Pending:** Task not yet started.
- ⚙️ **In Progress:** Task actively being worked on.
- ✅ **Completed:** Task finished successfully.
- ⚠️ **Issue:** Task encountered an issue requiring attention or a change in plan.
- ℹ️ **Info:** Documented finding or decision.

## Overall Goal

Enable the SwiftAudioPlayer core library to compile and function correctly on macOS, providing audio playback capabilities similar to its iOS counterpart, with necessary platform-specific adaptations.

---

## Phase 1: Project Setup and Initial Compilation

### 1.1. Modify `Package.swift` to include macOS platform

- Status: ✅
- Action:
  1.  Read `Package.swift` to understand current platform and Swift version settings.
  2.  Add `.macOS(.v10_15)` (or a suitable recent version) to the `platforms` array.
  3.  If a specific Swift version is declared, ensure it's compatible with the chosen macOS version.
- Implementation:
  ```swift
  platforms: [
      .iOS(.v15),
      .tvOS(.v10),
      .macOS(.v12)
  ],
  ```
- Verification: `swift package describe` (Completed successfully)
- Findings: ℹ️ Original `Package.swift` settings: `swift-tools-version:5.5`, `platforms: [.iOS(.v15), .tvOS(.v10)]`, `swiftLanguageVersions: [.v5]`.
- Decision: ℹ️ Added `.macOS(.v12)` to the platforms array.

### 1.2. Initial macOS Compilation Attempt

- Status: ✅
- Action: Attempt to build the project specifically for a macOS target.
- Command: `swift build --triple x86_64-apple-macosx`
- Expected Outcome: Compilation will likely fail, highlighting the first set of iOS-specific APIs.
- Actual Outcome & Errors: ⚠️ Compilation failed with multiple errors:
  1.  **`AVAudioSession` related errors in `SAPlayer.swift`**: All usages of `AVAudioSession`, its methods (`setCategory`, `setActive`, `sharedInstance`), and its enums/options (`.playback`, `.spokenAudio`, `.default`, `.allowAirPlay`) are unavailable in macOS.
  2.  **`NSImage` not found in `SAPlayerHelpers.swift`**: The conditional compilation for `artwork` (`UIImage` vs `NSImage`) fails because `NSImage` is not found in scope. This likely requires an `import AppKit` for macOS builds within this file/struct.
  3.  **`UIBackgroundTaskIdentifier` / `UIApplication` not found in `SAPlayerPresenter.swift`**: Despite the previous conditional import of `UIKit`, these types are still being referenced, indicating the scope of the conditional compilation needs review or the member accesses themselves are not properly guarded.
  4.  **`AudioConverter` errors in `Engine/Converter/AudioConverterErrors.swift`**: Constants `kAudioConverterErr_HardwareInUse` and `kAudioConverterErr_NoHardwarePermission` are not found. These are from `AudioToolbox` and their availability/naming on macOS needs checking.
- Next Steps based on errors:
  1.  Proceed with Phase 2 to address `AVAudioSession` errors.
  2.  Address `NSImage` errors (Phase 3/4).
  3.  Review and fix `UIBackgroundTaskIdentifier`/`UIApplication` usage (Phase 4).
  4.  Investigate and fix `AudioConverter` errors (New sub-task or part of Phase 5).

---

## Phase 2: Handling `AVAudioSession` (iOS/tvOS/watchOS specific)

### 2.1. Analyze and Adapt `AVAudioSession` Setup in `SAPlayer.swift`

- Status: ✅
- Context: `AVAudioSession` is used in `SAPlayer.swift`'s `becomeDeviceAudioPlayer()` method for category and activation.
- Action:
  1.  Read the `becomeDeviceAudioPlayer()` method in `SAPlayer.swift`.
  2.  Wrap `AVAudioSession.sharedInstance().setCategory(...)` and `AVAudioSession.sharedInstance().setActive(...)` calls with `#if os(iOS) || os(tvOS)`.
  3.  For macOS, these calls will be omitted. Audio playback on macOS typically doesn't require explicit session category management for basic functionality.
- Implementation Details: Wrapped the `do-catch` block inside `becomeDeviceAudioPlayer` with `#if os(iOS) || os(tvOS)`.
- Verification: `swift build --triple x86_64-apple-macosx` (Succeeded for this specific part; other errors remain).
- Findings: ℹ️ This change correctly isolates the session setup part.
- Decision: ℹ️ macOS will not perform explicit audio session category setup. System will use default behavior.

### 2.2. Analyze and Adapt `AVAudioSession` Interruption Handling in `SAPlayer.swift`

- Status: ✅
- Context: `SAPlayer.swift` observes `AVAudioSession.interruptionNotification` and uses related `AVAudioSession` types in `handleInterruption(notification:)` and `convertFromAVAudioSessionMode(_:)`.
- Action:
  1.  Read the `handleInterruption(notification:)` method, the `NotificationCenter.default.addObserver(...)` call for `AVAudioSession.interruptionNotification` in `init()`, and the `convertFromAVAudioSessionMode(_:)` helper.
  2.  Wrap all related code with `#if os(iOS) || os(tvOS)`.
- Implementation Details: Wrapped observer registration in `init()`, the `handleInterruption` method, and `convertFromAVAudioSessionMode` function with `#if os(iOS) || os(tvOS)`.
- Verification: `swift build --triple x86_64-apple-macosx` (Succeeded for this specific part; `AVAudioSession` errors are now resolved).
- Findings: ℹ️ All direct `AVAudioSession` related errors in `SAPlayer.swift` are resolved.
- Decision: ℹ️ macOS will not use `AVAudioSession`'s interruption mechanism.
- Future Consideration: Investigate macOS-specific audio interruption handling (e.g., observing `AVAudioEngineConfigurationChangeNotification`, or `NSWorkspace` notifications for other apps launching) if finer-grained control is needed later.

---

## Phase 3: Handling `MediaPlayer` Framework (MPNowPlayingInfoCenter & MPRemoteCommandCenter)

### 3.1. Analyze `MediaPlayer` framework usage

- Status: ✅
- Context: `LockScreenViewProtocol.swift` and `SAPlayerPresenter.swift` use `MPNowPlayingInfoCenter` and `MPRemoteCommandCenter`. These APIs are largely available on macOS for Notification Center's "Now Playing" widget and media key handling. Current compilation errors indicate issues with `MPMediaItemArtwork` initialization and `UIImage` usage within `LockScreenViewProtocol.swift` when targeting macOS.
- Action:
  1.  Read `LockScreenViewProtocol.swift` focusing on `setLockScreenInfo` and `MPMediaItemArtwork`.
  2.  Read `SAPlayerHelpers.swift` focusing on the `SALockScreenInfo` struct and its `artwork` property.
  3.  Modified `SAPlayerHelpers.swift`: Ensured `AppKit` is imported for macOS builds to make `NSImage` available. Refined conditional compilation for `artwork` type and initializer.
  4.  Modified `LockScreenViewProtocol.swift`: Added conditional `AppKit` import. Adapted `MPMediaItemArtwork` initialization for `NSImage`. Corrected `LockScreenViewPresenter` protocol definition by moving `setLockScreenInfo` back to `LockScreenViewProtocol` extension. Addressed `NSImage` cast warning and potential zero size for empty `NSImage`. Corrected optional binding for `NSImage`.
- Implementation Details:
  - `SAPlayerHelpers.swift`: Added conditional `import AppKit`. Refined `SALockScreenInfo.artwork` and `init` for `UIImage` (iOS/tvOS) vs `NSImage` (macOS).
  - `LockScreenViewProtocol.swift`: Added conditional `import AppKit`. Adapted `MPMediaItemArtwork` for platform-specific image types. Moved `setLockScreenInfo` to `LockScreenViewProtocol` extension. Removed redundant `as? NSImage` cast, handled empty `NSImage.size`, and fixed inner optional binding for `NSImage`.
- Verification: `swift build --triple x86_64-apple-macosx`. `NSImage`, `MPMediaItemArtwork`, and `LockScreenViewPresenter` conformance errors resolved. Optional binding error for `NSImage` resolved.
- Findings: ℹ️ Issues with `NSImage` availability and `MPMediaItemArtwork` initialization on macOS are addressed. Protocol definition corrected. Logic for handling `NSImage` in `MPMediaItemPropertyArtwork` corrected.
- Decision: Proceeding to Phase 4.

---

## Phase 4: Handling `UIKit` Dependencies

### 4.1. Review `UIBackgroundTaskIdentifier` Usage in `SAPlayerPresenter.swift`

- Status: ✅
- Context: `SAPlayerPresenter.swift` uses `UIBackgroundTaskIdentifier` and `UIApplication.shared.beginBackgroundTask`.
- Action:
  1.  Read `SAPlayerPresenter.swift` focusing on the `playNextAudioIfExists` method.
  2.  Ensured that the `import UIKit` is conditional (`#if os(iOS)`) and ALL code blocks that use `UIBackgroundTaskIdentifier` and `UIApplication` are wrapped in `#if os(iOS)`.
- Implementation Details: Wrapped `UIBackgroundTaskIdentifier` variable declaration and all `UIApplication.shared` calls related to background tasks in `playNextAudioIfExists` with `#if os(iOS)`.
- Verification: `swift build --triple x86_64-apple-macosx`. `UIBackgroundTaskIdentifier` and `UIApplication` errors resolved.
- Findings: ℹ️ Background task logic is iOS-specific and correctly excluded from macOS builds.
- Decision: Phase 4.1 complete. Proceed to Phase 4.2.

### 4.2. Global Search for Other `UIKit` Dependencies

- Status: ✅
- Action:
  1.  Performed a `grep_search` for `import UIKit` across the `Source/**/*.swift` files.
  2.  Reviewed search results.
- Implementation Details (if any): No new changes required.
- Verification: Grep results reviewed.
- Findings: ℹ️ All identified `import UIKit` statements in `LockScreenViewProtocol.swift`, `SAPlayerHelpers.swift`, and `SAPlayerPresenter.swift` are already within appropriate conditional compilation blocks (`#if os(iOS) || os(tvOS)` or `#if os(iOS)`).
- Decision: No further `UIKit` dependencies found that would block compilation. Phase 4 complete. Proceed to Phase 5.

---

## Phase 5: Build System and Final Compilation

### 5.1. Address Remaining Compilation Errors (Includes AudioConverter Errors)

- Status: ✅
- Context: Errors related to `kAudioConverterErr_HardwareInUse` and `kAudioConverterErr_NoHardwarePermission` in `Engine/Converter/AudioConverterErrors.swift` were the last blockers.
- Action:
  1.  Read `Engine/Converter/AudioConverterErrors.swift`.
  2.  Investigated the availability of these `AudioToolbox` constants on macOS.
  3.  Wrapped the usage of `kAudioConverterErr_HardwareInUse` and `kAudioConverterErr_NoHardwarePermission` in `#if os(iOS) || os(tvOS)` as they appear to be iOS/tvOS-specific.
- Implementation Details: Added `#if os(iOS) || os(tvOS)` around the two specific `case` statements in `localizedDescriptionFromConverterError` within `AudioConverterErrors.swift`.
- Verification: `swift build --triple x86_64-apple-macosx` resulted in a successful build.
- Findings & Fixes: ℹ️ The `AudioToolbox` constants `kAudioConverterErr_HardwareInUse` and `kAudioConverterErr_NoHardwarePermission` were confirmed to be unavailable/unnecessary for macOS compilation and were conditionally compiled out. The library now compiles successfully for `x86_64-apple-macosx`.

---

## Phase 6: Testing and Refinements (macOS)

### 6.1. Basic Playback Testing on macOS

- Status: ⏳
- Action: Create a minimal macOS command-line tool or a simple AppKit application within the `Example` or a new `ExampleMacOS` directory that uses `SwiftAudioPlayer` to:
  1.  Play a remote stream.
  2.  Play a local audio file.
  3.  Test basic controls: play, pause, seek.
  4.  Verify that `MediaPlayer` integration (Now Playing info, media keys) works as expected on macOS.
- Implementation Details:
- Verification: Manual testing of the example application.
- Findings:

### 6.2. Update `README.md` and `Package.swift`

- Status: ⏳
- Action:
  1.  Update `README.md` to mention macOS compatibility, any known limitations, or specific setup instructions for macOS.
  2.  Ensure `Package.swift` accurately reflects the supported macOS version (`.macOS(.v12)` as currently set).
- Implementation Details:
- Verification: Review of documentation and package manifest.
- Findings:

### 6.3. Consider macOS Specific Behaviors/APIs (Optional)

- Status: ⏳
- Action: Investigate if there are any macOS-specific audio behaviors or APIs that could enhance the library on this platform (e.g., deeper integration with system audio services, specific error handling, menu bar controls for a sample app).
- Implementation Details:
- Verification:
- Findings:

### 6.4. Gather Feedback & Address Issues

- Status: ⏳
- Action: If possible, test on different macOS versions and gather feedback. Address any runtime issues or unexpected behaviors found during testing.
- Implementation Details:
- Verification:
- Findings:

---

## Summary of Changes for macOS Porting (Core Library Compilation)

- **`Package.swift`**: Added `.macOS(.v12)` to supported platforms.
- **`Source/SAPlayer.swift`**:
  - Conditionally compiled out `AVAudioSession` setup (`setCategory`, `setActive`) for macOS using `#if os(iOS) || os(tvOS)`.
  - Conditionally compiled out `AVAudioSession` interruption handling (`interruptionNotification` observer, `handleInterruption` method, helper `convertFromAVAudioSessionMode`) for macOS using `#if os(iOS) || os(tvOS)`.
- **`Source/SAPlayerHelpers.swift`**:
  - Added conditional `import AppKit` for macOS.
  - Refined `SALockScreenInfo.artwork` to be `NSImage?` for macOS and `UIImage?` for iOS/tvOS.
  - Adjusted `SALockScreenInfo.init` for platform-specific artwork types.
- **`Source/LockScreenViewProtocol.swift`**:
  - Added conditional `import AppKit` for macOS.
  - Adapted `MPMediaItemArtwork` creation in `setLockScreenInfo` to handle `UIImage` (iOS/tvOS) and `NSImage` (macOS) correctly, including ensuring non-zero size for empty `NSImage`.
  - Corrected `LockScreenViewPresenter` protocol definition (moved `setLockScreenInfo` back to `LockScreenViewProtocol` extension).
  - Corrected `NSImage` optional binding within `setLockScreenInfo`.
- **`Source/SAPlayerPresenter.swift`**:
  - Conditionally compiled `import UIKit` to `#if os(iOS)`.
  - Conditionally compiled all usage of `UIBackgroundTaskIdentifier` and `UIApplication` (for background audio task management in `playNextAudioIfExists`) to `#if os(iOS)`.
- **`Source/Engine/Converter/AudioConverterErrors.swift`**:
  - Conditionally compiled out `case kAudioConverterErr_HardwareInUse` and `case kAudioConverterErr_NoHardwarePermission` from `localizedDescriptionFromConverterError` using `#if os(iOS) || os(tvOS)`.
