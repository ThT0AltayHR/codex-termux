---
name: Provider compatibility
description: Provider API compatibility constraint for the current Codex upstream.
---

The current upstream Codex configuration accepts `wire_api = "responses"` for model providers. Providers that expose only OpenAI-compatible Chat Completions endpoints should not be presented as guaranteed working integrations without an adapter.

**Why:** The configuration loader rejects the legacy chat wire API, so a hardcoded Groq or Gemini option could appear in the picker but fail when sending a request.

**How to apply:** Keep provider selection driven by configured providers, show safe API-key environment status only, and let the existing model catalog discover models for providers that the active wire protocol supports.