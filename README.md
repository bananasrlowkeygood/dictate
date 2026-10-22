# Dictate

Push-to-talk dictation for macOS. Speech is transcribed on-device with Parakeet TDT v2, cleaned up by a language model, and pasted where the cursor is.

## Use

| Action | Keys |
|---|---|
| Dictate | Hold Right ⌘, release to paste |
| Hands-free | Double-tap Right ⌘, tap again to finish |
| Cancel | Esc, or press any other key while holding Right ⌘ (normal shortcuts keep working) |
| Paste the raw transcript, no cleanup | Hold Shift at any point while dictating |

## Cleanup

Each transcript goes to the first of these that works:

1. Claude Haiku 5.5 (`claude-haiku-5-5`), needs internet and an API key
2. Apple's on-device model, used when offline or when the API fails
3. The raw transcript

Cleanup removes filler words, stutters and false starts, keeps self-corrections ("Tuesday, no, Wednesday" → "Wednesday"), and fixes punctuation. It doesn't reword. The prompt is in `Sources/Dictate/Polisher.swift`.

The API key is stored in the login keychain:

```
security add-generic-password -U -s com.ravibandaru.dictate -a anthropic-api-key -T /Applications/Dictate.app -w
```

## Build

```
./build.sh
```

Builds, signs with the Apple Development certificate (so Accessibility and Microphone permissions survive rebuilds), installs to `/Applications` and restarts the LaunchAgent `~/Library/LaunchAgents/com.ravibandaru.dictate.plist`.

Log: `~/Library/Logs/Dictate.log`. It records which cleanup path ran and how long it took, never the text.

`backup/` holds the previous build (1.0, no cleanup).
