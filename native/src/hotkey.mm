// Murmur global modifier-hotkey addon (macOS).
//
// A direct port of the Swift HotkeyMonitor's `.modifier` branch: a session-level
// CGEventTap listening on .flagsChanged for the down-edge of one bare modifier
// key (e.g. Right Option), emitting a "toggle" to JS. Modifier-only events flow
// to session taps even for non-notarized apps on macOS 26 (unlike .keyDown,
// which Tahoe drops) — which is exactly why we listen on .flagsChanged only and
// never consume events.
//
// Threading: the tap's run-loop source is attached to CFRunLoopGetMain() —
// Electron's main process already pumps the main CFRunLoop (integrated with
// libuv), so the callback fires on the main/JS thread. We still hop to JS via a
// Napi::ThreadSafeFunction rather than calling V8 from the run-loop callback.
#include <napi.h>
#import <Foundation/Foundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <CoreFoundation/CoreFoundation.h>

using namespace Napi;

static CFMachPortRef gTap = nullptr;
static CFRunLoopSourceRef gSource = nullptr;
static ThreadSafeFunction gTsfn;
static bool gInstalled = false;
static bool gModifierHeld = false;     // for down-edge detection on .flagsChanged
static uint16_t gTargetKeycode = 61;   // default: Right Option (alt_r)

// Which CGEventFlags bit a given modifier keycode toggles (Swift parity).
static CGEventFlags bitForKeycode(uint16_t kc) {
  switch (kc) {
    case 54: case 55: return kCGEventFlagMaskCommand;   // Right/Left Command
    case 58: case 61: return kCGEventFlagMaskAlternate; // Left/Right Option
    case 59: case 62: return kCGEventFlagMaskControl;   // Left/Right Control
    case 56: case 60: return kCGEventFlagMaskShift;     // Left/Right Shift
    default:          return 0;
  }
}

static CGEventRef TapCallback(CGEventTapProxy, CGEventType type, CGEventRef event, void*) {
  // System throttled/disabled the tap — re-arm so the hotkey keeps working.
  if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) {
    if (gTap) CGEventTapEnable(gTap, true);
    return event;
  }
  if (type != kCGEventFlagsChanged) return event;

  uint16_t kc = (uint16_t)CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);
  if (kc != gTargetKeycode) return event;

  CGEventFlags bit = bitForKeycode(kc);
  bool isDown = bit != 0 && (CGEventGetFlags(event) & bit) != 0;

  if (isDown && !gModifierHeld) {
    gModifierHeld = true;
    if (gInstalled) {
      gTsfn.NonBlockingCall([](Env env, Function cb) {
        cb.Call({ String::New(env, "toggle") });
      });
    }
  } else if (!isDown) {
    gModifierHeld = false;
  }
  // Never consume modifier-only events (users chord ⌥/⌘ for normal shortcuts).
  return event;
}

// install(targetKeycode: number, callback: (event: string) => void) -> boolean
Value Install(const CallbackInfo& info) {
  Env env = info.Env();
  if (gInstalled) return Napi::Boolean::New(env, true);

  uint16_t keycode = (uint16_t)info[0].As<Number>().Uint32Value();
  gTsfn = ThreadSafeFunction::New(env, info[1].As<Function>(), "MurmurHotkey", 0, 1);

  gTap = CGEventTapCreate(
      kCGSessionEventTap, kCGHeadInsertEventTap,
      kCGEventTapOptionListenOnly,                 // listen-only: we never consume
      CGEventMaskBit(kCGEventFlagsChanged),
      TapCallback, nullptr);

  if (!gTap) {                                     // Accessibility not granted
    gTsfn.Release();
    gTsfn = ThreadSafeFunction();
    return Napi::Boolean::New(env, false);         // leave globals untouched on failure
  }

  // Commit state only now that the tap exists.
  gTargetKeycode = keycode;
  gModifierHeld = false;

  // Defensive: never overwrite a live source (normal flow has gSource == null).
  if (gSource) {
    CFRunLoopRemoveSource(CFRunLoopGetMain(), gSource, kCFRunLoopCommonModes);
    CFRelease(gSource);
    gSource = nullptr;
  }
  gSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, gTap, 0);
  CFRunLoopAddSource(CFRunLoopGetMain(), gSource, kCFRunLoopCommonModes);
  CGEventTapEnable(gTap, true);
  gInstalled = true;
  return Napi::Boolean::New(env, true);
}

// uninstall() -> void
Value Uninstall(const CallbackInfo& info) {
  Env env = info.Env();
  if (!gInstalled) return env.Undefined();
  gInstalled = false;
  if (gTap) CGEventTapEnable(gTap, false);
  if (gSource) {
    CFRunLoopRemoveSource(CFRunLoopGetMain(), gSource, kCFRunLoopCommonModes);
    CFRelease(gSource);
    gSource = nullptr;
  }
  if (gTap) {
    CFRelease(gTap);
    gTap = nullptr;
  }
  gTsfn.Release();
  gTsfn = ThreadSafeFunction();
  gModifierHeld = false;
  return env.Undefined();
}

// paste() -> boolean : synthesize ⌘V into the focused app (Swift Paster parity:
// combined-session source, V keycode 9, Command flag, posted to the annotated
// session tap so it reaches the focused app and isn't swallowed by our own tap).
Value Paste(const CallbackInfo& info) {
  Env env = info.Env();
  CGEventSourceRef src = CGEventSourceCreate(kCGEventSourceStateCombinedSessionState);
  if (!src) return Napi::Boolean::New(env, false);

  const CGKeyCode kVKeyCodeV = 9;  // 'V' on a US layout (translated by position)
  CGEventRef down = CGEventCreateKeyboardEvent(src, kVKeyCodeV, true);
  CGEventRef up = CGEventCreateKeyboardEvent(src, kVKeyCodeV, false);
  if (!down || !up) {
    if (down) CFRelease(down);
    if (up) CFRelease(up);
    CFRelease(src);
    return Napi::Boolean::New(env, false);
  }
  CGEventSetFlags(down, kCGEventFlagMaskCommand);
  CGEventSetFlags(up, kCGEventFlagMaskCommand);
  CGEventPost(kCGAnnotatedSessionEventTap, down);
  CGEventPost(kCGAnnotatedSessionEventTap, up);
  CFRelease(down);
  CFRelease(up);
  CFRelease(src);
  return Napi::Boolean::New(env, true);
}

Object Init(Env env, Object exports) {
  exports.Set("install", Function::New(env, Install));
  exports.Set("uninstall", Function::New(env, Uninstall));
  exports.Set("paste", Function::New(env, Paste));
  return exports;
}

NODE_API_MODULE(hotkey, Init)
