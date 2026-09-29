# Jira Query Watcher

A Flutter macOS utility that periodically queries Jira with JQL and sends a native macOS notification when the result set or an issue status changes.

## Features

- Jira Cloud using email + API token
- Jira Server / Data Center using a bearer personal access token
- JQL polling every 1–30 minutes
- Difference detection by issue key and status
- Token stored in macOS Keychain
- Native macOS notifications
- Window close hides the app so monitoring continues
- Optional launch at login on macOS 13+

The first successful query creates a baseline and does not send a change notification. Later notifications cover added or removed issues, replacements with the same result count, and issue status changes. The baseline is persisted so changes can be detected after restarting the app.

## Run

```sh
fvm flutter run -d macos
```

## Verify

```sh
fvm flutter analyze
fvm flutter test
fvm flutter build macos
```
