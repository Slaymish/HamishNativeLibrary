# Provider access and a future connection

Verified 11 October 2026. Capability availability and terms change; re-check these links before implementing
a remote adapter. The current package uses user-controlled prompts and files with no API credentials.

## What sign-in can mean

OpenAI documents a Sign in with ChatGPT route for eligible plan-backed inference. Its open-source client
flow uses browser consent, PKCE, a stable host ID and validated identity tokens. Listed scopes cover
identity and inference, not an arbitrary `memory.read` or `memory.write` permission. This is a promising
future macOS adapter, not evidence of consumer-memory access. The documented loopback callback also
needs separate feasibility work for iOS. [Registration and sign-in](https://developers.openai.com/siwc/token-sharing-open-source/sign-in).

The preview inference route requires explicit context per request and has restricted conversation/tool
support. It does not establish persistent access to the person's chat history. Check account eligibility,
branding and supported platforms before showing a real login button. [Preview limitations](https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations).

Claude's guidance identifies API keys or a supported cloud provider as the preferred route for third-party
tools. A Claude subscription login used by Anthropic applications is not a general permission to reuse its
OAuth token in another app. Do not read Claude Code's stored credentials to build a connector.
[Claude account authentication](https://support.claude.com/en/articles/13189465-log-in-to-your-claude-account).

Another direction is to expose scoped app tools to ChatGPT through an authenticated MCP server/plugin.
That makes your app's data/tools available to the agent; it does not confer a consumer-memory API on the
native app. [OpenAI plugin development](https://developers.openai.com/plugins).

## Architecture for the next experiment

Keep three capabilities separate: authenticating the person, permission to exchange app context, and
permission to a specific provider endpoint. Provider-issued granted scopes must be checked after login;
an app's permission toggles cannot create provider permissions.

Use the existing `ExchangePermission` and native consent UI for app-side scope. A future transport should
declare actual capabilities and return real receipts: identity, inference, app-context tools, verified
memory reads/writes if supported, and background execution. Disable unavailable capabilities in UI.
Do not name placeholder permissions after endpoints that do not exist.

For a real OAuth adapter, use system browser authentication, PKCE, per-attempt state/nonce, exact redirect
matching, validated issuer/audience/signature/expiry, granted-scope checks, Keychain tokens, refresh/revoke
handling and account separation. Follow that provider's documented native flow; do not ship a shared client
secret in a binary. This release includes Keychain storage, not an untested token-exchange implementation.

The useful next demonstration is fictional context imported → explicit native correction → authorised
write through a verified memory tool → another app receiving the correction. Include denial, conflict,
revocation and failed-write cases. Until a memory tool returns success, display “correction proposed” rather
than “memory synced”. The native example already demonstrates consent and reviewed app-side updates.
