# Privacy and diagnostics

What the AnyRouter app collects, where it goes, and how to turn it off.

## What never leaves your device

- Chats, prompts and replies. Local models (Apple, GGUF, MLX) run on the device. A message leaves it only when you pick an AnyRouter cloud model, and then it goes to AnyRouter to be answered.
- Your AnyRouter sign-in key. It lives in the Keychain.
- Prompts, keys, tokens and email addresses are never written to logs, events, crash reports or breadcrumbs.

## On the device only

- **Logs.** `os.Logger` with the categories `auth`, `chat`, `engine`, `download`, `mcp` and `app`, subsystem `dev.anyrouter.app`. They stay in the system log.
- **Crash, hang and metric reports.** iOS (MetricKit) hands the app reports about crashes, hangs, CPU and disk exceptions, and daily metrics, usually the day after. The app keeps the newest 20 as JSON in its own storage. See them in **Settings, Diagnostics**, and share one with the share button. Nothing is sent unless you share it. They are deleted with the app.

## Optional remote reporting (Sentry)

Off unless the build has a Sentry DSN (`SENTRY_DSN`) **and you say yes**. A build without a DSN starts no SDK and makes no network calls for diagnostics. Builds from this repository have no DSN unless the person building sets one.

Even with a DSN, sharing is **off by default**. After your first successful chat the app asks once: "Help improve AnyRouter? Share anonymous crash reports and timings. No messages, keys or emails." Choose Share or Not now. The answer is remembered and the question is not asked again. You can change it any time in **Settings, Privacy, Share anonymous diagnostics**.

When a DSN is set and you chose to share, the app sends:

- Crash and app hang reports from the Sentry SDK.
- Breadcrumbs for these events only: `app_open`, `sign_in_ok`, `sign_in_fail` (a short reason code), `model_selected` (source: apple, gguf, mlx or anyrouter), `message_sent` (source only), `first_token_ms`, `engine_load_ms`, `download_ok`, `download_fail` (reason code), `crash_seen` (kind).

Settings of the SDK: no personal data (`sendDefaultPii` off), no IP address collection, no screenshots or view hierarchy, no network or tap breadcrumbs, no performance traces, no session tracking. Breadcrumb text and data are scrubbed of URL query strings and bearer tokens before they are sent.

Sentry is the only third-party service. There is no analytics SDK.

## Turn it off

- **Settings, Privacy, Share anonymous diagnostics** off. Events and crash reports are dropped from then on. The SDK itself stops at the next launch. Turning the switch on (or answering Share) starts it at the next launch.
- Or build without a DSN: leave `SENTRY_DSN` empty in `Config/Local.xcconfig` (see `Config/Local.xcconfig.example`) and unset the `SENTRY_DSN` repository secret.
