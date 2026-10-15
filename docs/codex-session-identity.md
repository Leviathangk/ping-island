# Codex session identity and auxiliary tasks

## Desktop branding and compatibility

The desktop client is displayed as **ChatGPT**. Its macOS bundle identifier remains
`com.openai.codex`, its thread links remain `codex://threads/<id>`, and its bundled
CLI is still named `codex`. Discovery prefers `ChatGPT.app` and retains `Codex.app`
as a fallback, validating the bundle identity before using an embedded executable.
Keep the persisted `codex-app` profile, `.codexApp` kind, Codex provider, and CLI
identifiers stable. Old desktop names normalize to ChatGPT when associations load;
legacy `Codex Desktop` originators remain supported alongside ChatGPT metadata.
Source badges also display legacy desktop aliases as ChatGPT without rewriting
raw originators, including remote CLI snapshots.
Actual TTY, terminal session, and tmux evidence still preserve Codex CLI routing.

## Host evidence

`HookPayloadMapper` recognizes Qoder and Qoder CN hosts from explicit bundle
identifiers or IDE IPC / AskPass executable paths. Merely inheriting a variable
whose name starts with `QODER_`, `QODER_CN_`, or `QODERCN_` does not identify an
IDE, regardless of whether its value is `1`, `0`, or another value. Parent-process
context capture remains in the bridge. Standalone terminals retain priority over
unrelated IDE hints.

`HookSocketServer` combines ChatGPT desktop source metadata with actual terminal
evidence. An IDE bundle alone cannot turn a known desktop session into a CLI
session. A TTY, terminal program, terminal session identifier, or tmux context
preserves real IDE-hosted CLI sessions. The optional `SessionClientInfo.terminalTTY`
field carries TTY evidence across snapshots and cache reloads; old JSON without
this field remains readable.

## Repairing cached routing

`SessionClientInfo.normalizedForCodexRouting` repairs a stored identity when its
own desktop evidence is sufficient. `SessionAssociationStore` applies this repair
on load and writes back changed associations. Ambiguous old records wait for new
source evidence rather than changing identity solely because they mention Qoder.

`SessionStore.normalizedCodexClientInfo` reconciles new desktop evidence with both
cached and live identities. Confirmed contaminated records receive the canonical
ChatGPT desktop profile and thread link, and lose the false Qoder terminal host and
workspace URL. Real CLI terminal evidence is preserved. Session paths, remote
transport, names of user tasks, and conversation state remain available.

Ordinary `SessionClientInfo.merged` calls preserve old values when an incoming
optional field is absent. A confirmed repair uses `replacingRouting: true` so
absent routing fields explicitly clear stale values. Summary and full-snapshot
ingestion assign the reconciled result directly, avoiding a second merge that
would resurrect those values.

## Auxiliary tasks

`CodexAuxiliaryHookFilter` uses exact internal task sources and anchored dedicated
opening prompts, including title generation, ambient suggestions, and
`composer_predictions` input-composer predictions. Composer predictions fork an
existing task, inherit its project and messages, and return a singular
`suggestion` JSON field. Filter their exact task source even when the opening
prompt looks like an ordinary inherited request or no rollout file exists; the
dedicated app-generated next-message opening also identifies source-less hooks.
The JSON field alone is not auxiliary-task evidence. These tasks can use normal
project directories and tools; neither is proof of user intent.
Conversely, JSON containing `title`, `suggestion`, `suggestions`, `include`, or `exclude` is not
proof of an internal task. `ambient_suggestion_task` denotes a task accepted by
the user and must remain visible. Blocking questions and approvals retain their
existing protection from filtering. When app-server list or start metadata
identifies a helper already in the store, remove its old row through the shared
auxiliary-session cleanup; preserve rows with an unanswered prompt. Cleanup
severs stale helper aliases without deleting the real task they pointed at, and
skips helper list candidates whose ID also has an accepted duplicate candidate.

## Terminal-only prompts and list access

`suppressInAppPromptControls` identifies a prompt whose answer stays in the client.
Without an approval or question intervention, it contributes to attention only
while the session is waiting for input. Fresh Codex progress/completion updates
and explicit request resolution clear that flag; older snapshots preserve newer
unanswered prompts. This keeps a resolved, idle thread from holding a green bell
and an empty attention card indefinitely.

The hook's `suppress_in_app_prompt` metadata is a routing policy, not evidence of
an unanswered prompt. Only recognized native question tools, approvals, or
explicit interventions establish terminal-only attention. An ordinary `Stop`
clears it when no real intervention remains, even if the routing policy is still
enabled. Idle notifications preserve an existing native question without
creating a reminder for a completed turn. Diagnostic session snapshots include
the prompt flag, its attention result, and the thread source.

Automatic notifications and hover still prioritize unanswered prompts. Clicking
or using the session-list shortcut opens the full list, where existing approval
and question controls remain available. Switching an already-open completion
notification to manual browsing also consumes the notification and cancels its
dismissal timer.

## Verification

- `swift test --package-path Prototype` covers statistics flags, multiple inherited
  variables, explicit bundle / IPC hosts, and standalone terminals.
- `HookSocketServerClientInfoTests` covers desktop versus real IDE terminal input.
- `ClientProfileMatchingTests` covers cache repair, nullable routing replacement,
  legacy decoding, and CLI preservation.
- `CodexHookSessionTests` covers repair of already-live rows through hooks, thread
  summaries, and complete snapshots.
- Auxiliary filter, app-server monitor, rollout parser, placeholder, and
  session-state tests cover helper sources and prompts alongside ordinary JSON
  and user-created tasks, including composer predictions without rollout files.
- Session-state, Codex-intervention, attention tracker/sound, and expanded-route
  tests cover stale prompt flags, fresh versus older updates, and manual list access.
