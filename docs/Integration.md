# Integration and audio boundaries

Auralis is an unofficial development client. The first-party YouTube Music website owns sign-in, playback, advertising and subscription checks inside WKWebView. Successful in-app sign-in, normal quit/relaunch persistence and a complete Premium-track playback were observed on the development Mac. This is account-specific evidence, not a guarantee of Google's future support or approval.

The initial investigation inspected [Kaset's login view](https://github.com/sozercan/kaset/blob/4c59ff259d853f1cc328597f5adccf2a291c2fa7/Sources/Kaset/Views/LoginWebView.swift). Auralis uses a shared persistent WebKit store, direct ServiceLogin and an installed-Safari-compatible user agent. It does not copy a private API layer, cookie backup or credential capture.

Google's [OAuth policy](https://developers.google.com/identity/protocols/oauth2/policies) restricts developer-controlled embedded authorization. This app loads the first-party website session, without registering an OAuth client or acquiring API streaming scopes. A successful website session does not constitute policy clearance. Challenges or rejection remain visible; there is no authentication bypass.

The provider's [audio quality help](https://support.google.com/youtubemusic/answer/9076559) documents Low/Normal/High Premium settings with upper bounds of 48/128/256 kbps AAC or Opus in its Android instructions. These are not measurements of the desktop stream. Auralis neither forces a tier nor claims a verified bitrate, lossless output or bit-perfect playback.

Public [HTMLMediaElement](https://html.spec.whatwg.org/multipage/media.html#htmlmediaelement) properties and [Media Session metadata](https://www.w3.org/TR/mediasession/) supply timing and presentation, not PCM access or a streaming SDK. Apple's [WKWebView](https://developer.apple.com/documentation/webkit/wkwebview) performs playback; [MPRemoteCommandCenter](https://developer.apple.com/documentation/mediaplayer/mpremotecommandcenter) supplies system callbacks, with ownership arbitrated by macOS.

All animation is time/theme/playback-state driven. There is no FFT, beat detection, microphone or system recording. [Web Audio's cross-origin rules](https://www.w3.org/TR/webaudio/#MediaElementAudioSourceNode-security) prevent assuming that an accessible media element exposes analyzable audio. [ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit) would be a separate recording feature and is not used.

The [YouTube terms](https://www.youtube.com/t/terms) and [developer policy guide](https://developers.google.com/youtube/terms/developer-policies-guide) remain relevant. This project does not claim an approved integration or independent streaming entitlement. DOM compatibility can change. No private streaming extraction, DRM bypass, ad blocker or quality spoofing is implemented.

Integration research was checked on 25 October 2026; runtime observations and current engineering checks are recorded in [Validation.md](Validation.md).
