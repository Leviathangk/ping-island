import XCTest
@testable import Ping_Island

final class CodexHookPlaceholderTests: XCTestCase {
    func testWeakCodexSessionStartSeedsPlaceholderSession() async {
        let sessionId = "codex-start-\(UUID().uuidString)"
        let store = SessionStore.shared

        await store.process(.hookReceived(
            makeCodexEvent(
                sessionId: sessionId,
                event: "SessionStart",
                status: "waiting_for_input"
            )
        ))

        let session = await store.session(for: sessionId)
        XCTAssertEqual(session?.provider, .codex)
        XCTAssertEqual(session?.phase, .waitingForInput)
        XCTAssertEqual(session?.ingress, .hookBridge)

        await store.process(.sessionArchived(sessionId: sessionId))
    }

    func testWeakCodexUserPromptSubmitSeedsPlaceholderSession() async {
        let sessionId = "codex-prompt-\(UUID().uuidString)"
        let store = SessionStore.shared

        await store.process(.hookReceived(
            makeCodexEvent(
                sessionId: sessionId,
                event: "UserPromptSubmit",
                status: "processing"
            )
        ))

        let session = await store.session(for: sessionId)
        XCTAssertEqual(session?.provider, .codex)
        XCTAssertEqual(session?.phase, .processing)
        XCTAssertEqual(session?.ingress, .hookBridge)

        await store.process(.sessionArchived(sessionId: sessionId))
    }

    func testCodexTitleGenerationPromptIsStillIgnored() async {
        let sessionId = "codex-title-\(UUID().uuidString)"
        let store = SessionStore.shared

        await store.process(.hookReceived(
            makeCodexEvent(
                sessionId: sessionId,
                event: "UserPromptSubmit",
                status: "processing",
                message: """
                You are a helpful assistant. You will be presented with a user prompt, and your job is to provide a short title for a task that will be created from that prompt.
                Generate a concise UI title (18-36 characters) for this task.
                Return only the title. No quotes or trailing punctuation.
                """
            )
        ))

        let session = await store.session(for: sessionId)
        XCTAssertNil(session)
    }

    func testSuggestionHookRemovesPlaceholderAndIgnoresToolAndCompletionEvents() async {
        let sessionId = "suggestion-\(UUID().uuidString)"
        let store = SessionStore.shared
        await store.process(.hookReceived(makeCodexEvent(sessionId: sessionId, event: "SessionStart", status: "waiting_for_input")))
        await store.process(.hookReceived(makeCodexEvent(sessionId: sessionId, event: "UserPromptSubmit", status: "processing",
            message: "# Overview\n\nGenerate 0 to 3 hyperpersonalized suggestions for what this user can do with Codex in this local project: /tmp/project")))
        await store.process(.hookReceived(makeCodexEvent(sessionId: sessionId, event: "PostToolUse", status: "processing", message: "Read files")))
        await store.process(.hookReceived(makeCodexEvent(sessionId: sessionId, event: "Stop", status: "waiting_for_input", message: #"{"suggestions":[]}"#)))
        let session = await store.session(for: sessionId)
        XCTAssertNil(session)
    }

    func testTitleHelperSourceIsIgnoredWithPersistedRolloutAndNoOpeningPrompt() async {
        let sessionId = "title-source-\(UUID().uuidString)"
        let store = SessionStore.shared
        await store.process(.hookReceived(makeCodexEvent(
            sessionId: sessionId, event: "SessionStart", status: "processing",
            threadSource: "thread_title", sessionFilePath: "/tmp/project/title-helper.jsonl"
        )))
        let session = await store.session(for: sessionId)
        XCTAssertNil(session)
    }

    func testNormalJSONResponsesAndRootWorkspaceAreNotAuxiliaryEvidence() async {
        let store = SessionStore.shared
        for message in [#"{"title":"Project title"}"#, #"{"suggestions":[]}"#, #"{"exclude":[]}"#] {
            let sessionId = "json-task-\(UUID().uuidString)"
            await store.process(.hookReceived(makeCodexEvent(
                sessionId: sessionId, event: "UserPromptSubmit", status: "processing",
                message: message, cwd: "/", threadSource: "ambient_suggestion_task"
            )))
            let session = await store.session(for: sessionId)
            XCTAssertNotNil(session)
            XCTAssertFalse(session?.shouldHideFromPrimaryUI ?? true)
            await store.process(.sessionArchived(sessionId: sessionId))
        }
    }

    func testComposerPredictionSourceFiltersHooksAndAppServerSummaries() async {
        let store = SessionStore.shared
        let sessionId = "composer-prediction-\(UUID().uuidString)"
        let preview = #"{"suggestion":"Continue the task"}"#
        await store.process(.hookReceived(makeCodexEvent(
            sessionId: sessionId, event: "UserPromptSubmit", status: "processing",
            message: "An inherited user request", threadSource: "composer_predictions"
        )))
        await store.process(.hookReceived(makeCodexEvent(
            sessionId: sessionId, event: "Stop", status: "waiting_for_input", message: preview
        )))
        let hooked = await store.session(for: sessionId)
        XCTAssertNil(hooked)

        var client = SessionClientInfo.codexApp(threadId: sessionId)
        client.threadSource = "composer_predictions"
        await store.upsertCodexSession(
            sessionId: sessionId, name: "project", preview: preview, cwd: "/tmp/project",
            phase: .idle, intervention: nil, clientInfo: client
        )
        let summarized = await store.session(for: sessionId)
        XCTAssertNil(summarized)
        await store.process(.sessionArchived(sessionId: sessionId))
    }

    func testComposerPredictionOpeningRemovesPlaceholderWithoutSourceOrRolloutPath() async {
        let store = SessionStore.shared
        let sessionId = "composer-opening-\(UUID().uuidString)"
        let cwd = "/tmp/composer-opening-\(UUID().uuidString)"
        await store.process(.hookReceived(makeCodexEvent(
            sessionId: sessionId, event: "SessionStart", status: "waiting_for_input", cwd: cwd
        )))
        let placeholder = await store.session(for: sessionId)
        XCTAssertNotNil(placeholder)

        let prompt = "This is an app-generated request for a suggested next user message. The user did not write this message. Your suggestion will appear in the user's empty message composer. They can accept it, edit it, or ignore it; it will not be sent automatically. Predict the single message this user is most likely to type next from the visible conversation. Use the whole conversation to understand their current intent and the latest exchange."
        await store.process(.hookReceived(makeCodexEvent(
            sessionId: sessionId, event: "UserPromptSubmit", status: "processing", message: prompt, cwd: cwd
        )))
        let filtered = await store.session(for: sessionId)
        XCTAssertNil(filtered)

        for event in ["PreToolUse", "PostToolUse", "Stop"] {
            await store.process(.hookReceived(makeCodexEvent(
                sessionId: sessionId, event: event,
                status: event == "Stop" ? "waiting_for_input" : "processing",
                message: event == "Stop" ? #"{"suggestion":"Continue the task"}"# : "Read project files",
                cwd: cwd
            )))
            let session = await store.session(for: sessionId)
            XCTAssertNil(session, event)
        }
        await store.process(.sessionArchived(sessionId: sessionId))
    }

    func testNormalSingularSuggestionJSONRemainsVisibleWithoutSourceOrRolloutPath() async {
        let store = SessionStore.shared
        let sessionId = "user-suggestion-json-\(UUID().uuidString)"
        let cwd = "/tmp/user-suggestion-json-\(UUID().uuidString)"
        await store.process(.hookReceived(makeCodexEvent(
            sessionId: sessionId, event: "UserPromptSubmit", status: "processing",
            message: "Return a JSON suggestion for the next project task", cwd: cwd
        )))
        await store.process(.hookReceived(makeCodexEvent(
            sessionId: sessionId, event: "Stop", status: "waiting_for_input",
            message: #"{"suggestion":"Continue the task"}"#, cwd: cwd
        )))
        let session = await store.session(for: sessionId)
        XCTAssertNotNil(session)
        XCTAssertFalse(session?.shouldHideFromPrimaryUI ?? true)
        await store.process(.sessionArchived(sessionId: sessionId))
    }

    func testAuxiliaryCleanupSeversTransientHookAliasWithoutRemovingRealTask() async {
        let store = SessionStore.shared
        let realId = "real-task-\(UUID().uuidString)"
        let helperId = "prediction-alias-\(UUID().uuidString)"
        let cwd = "/tmp/prediction-alias-\(UUID().uuidString)"
        await store.upsertCodexSession(
            sessionId: realId, name: "Real task", preview: "Real user work",
            cwd: cwd, phase: .idle, intervention: nil
        )
        await store.process(.hookReceived(makeCodexEvent(
            sessionId: helperId, event: "UserPromptSubmit", status: "processing", cwd: cwd
        )))
        let aliased = await store.resolvedCodexSessionId(for: helperId)
        XCTAssertEqual(aliased, realId)

        await store.removeCodexAuxiliarySession(sessionId: helperId)
        let realTask = await store.session(for: realId)
        let helper = await store.session(for: helperId)
        XCTAssertEqual(realTask?.sessionName, "Real task")
        XCTAssertNil(helper)

        // A pending request addressed through the alias still needs that route
        // when the client later resolves it.
        await store.process(.hookReceived(makeCodexEvent(
            sessionId: helperId, event: "UserPromptSubmit", status: "processing", cwd: cwd
        )))
        await store.upsertCodexSession(
            sessionId: helperId, name: nil, preview: "Continue?", cwd: cwd,
            phase: .waitingForInput, intervention: SessionIntervention(
                id: "request", kind: .question, title: "Choice", message: "Continue?",
                options: [], questions: [], supportsSessionScope: false, metadata: [:]
            )
        )
        await store.removeCodexAuxiliarySession(sessionId: helperId)
        let pendingAlias = await store.resolvedCodexSessionId(for: helperId)
        XCTAssertEqual(pendingAlias, realId)
        await store.resolveCodexIntervention(sessionId: helperId, nextPhase: .processing, requestId: "request")
        let resolvedTask = await store.session(for: realId)
        XCTAssertNotNil(resolvedTask)
        XCTAssertNil(resolvedTask?.intervention)
        await store.process(.sessionArchived(sessionId: realId))
    }

    func testCodexMemoryMaintenanceHookIsIgnored() async {
        let sessionId = "codex-memory-\(UUID().uuidString)"
        let store = SessionStore.shared

        await store.process(.hookReceived(
            makeCodexEvent(
                sessionId: sessionId,
                event: "SessionStart",
                status: "waiting_for_input",
                cwd: "/tmp/ping-island-home/.codex/memories"
            )
        ))

        await store.process(.hookReceived(
            makeCodexEvent(
                sessionId: sessionId,
                event: "Stop",
                status: "waiting_for_input",
                message: "Created MEMORY.md and memory_summary.md from the new inputs.",
                cwd: "/tmp/ping-island-home/.codex/memories"
            )
        ))

        let session = await store.session(for: sessionId)
        XCTAssertNil(session)
    }

    func testCodexMemoryMaintenanceAppServerUpsertIsIgnored() async {
        let sessionId = "codex-memory-upsert-\(UUID().uuidString)"
        let store = SessionStore.shared

        await store.upsertCodexSession(
            sessionId: sessionId,
            name: "memories",
            preview: "Created MEMORY.md and memory_summary.md from the new inputs.",
            cwd: "/tmp/ping-island-home/.codex/memories",
            phase: .waitingForInput,
            intervention: nil,
            clientInfo: SessionClientInfo.codexApp(threadId: sessionId)
        )

        let session = await store.session(for: sessionId)
        XCTAssertNil(session)
    }

    func testCodexMemoryMaintenanceSnapshotIsIgnored() async {
        let sessionId = "codex-memory-snapshot-\(UUID().uuidString)"
        let store = SessionStore.shared

        await store.syncCodexThreadSnapshot(CodexThreadSnapshot(
            threadId: sessionId,
            name: "memories",
            preview: "Created MEMORY.md and memory_summary.md from the new inputs.",
            cwd: "/tmp/ping-island-home/.codex/memories",
            clientInfo: SessionClientInfo.codexApp(threadId: sessionId),
            intervention: nil,
            createdAt: Date(),
            updatedAt: Date(),
            phase: .waitingForInput,
            historyItems: [],
            conversationInfo: ConversationInfo(
                summary: "memories",
                lastMessage: "Created MEMORY.md and memory_summary.md from the new inputs.",
                lastMessageRole: "assistant",
                lastToolName: nil,
                firstUserMessage: "update memory",
                lastUserMessageDate: Date()
            ),
            latestTurnId: nil,
            latestResponseText: "Created MEMORY.md and memory_summary.md from the new inputs.",
            latestResponsePhase: "final",
            latestUserText: "update memory"
        ))

        let session = await store.session(for: sessionId)
        XCTAssertNil(session)
    }

    func testSuggestionSnapshotRemovesPreviouslyIngestedSession() async {
        let sessionId = "codex-memory-snapshot-\(UUID().uuidString)"
        let store = SessionStore.shared

        await store.upsertCodexSession(sessionId: sessionId, name: "project", preview: "Working", cwd: "/tmp/project", phase: .processing, intervention: nil)
        await store.syncCodexThreadSnapshot(CodexThreadSnapshot(
            threadId: sessionId,
            name: "project",
            preview: "No suggestions available.",
            cwd: "/tmp/project",
            clientInfo: SessionClientInfo.codexApp(threadId: sessionId),
            intervention: nil,
            createdAt: Date(),
            updatedAt: Date(),
            phase: .waitingForInput,
            historyItems: [],
            conversationInfo: ConversationInfo(
                summary: "project",
                lastMessage: "No suggestions available.",
                lastMessageRole: "assistant",
                lastToolName: nil,
                firstUserMessage: "# Overview\n\nGenerate 0 to 3 hyperpersonalized suggestions for what this user can do with Codex in this local project: /tmp/project",
                lastUserMessageDate: Date()
            ),
            latestTurnId: nil,
            latestResponseText: "No suggestions available.",
            latestResponsePhase: "final",
            latestUserText: "# Overview\n\nGenerate 0 to 3 hyperpersonalized suggestions for what this user can do with Codex in this local project: /tmp/project"
        ))

        let session = await store.session(for: sessionId)
        XCTAssertNil(session)
    }

    func testTitleSnapshotRemovesPreviouslyIngestedSessionByOpeningPrompt() async {
        let sessionId = "codex-title-snapshot-\(UUID().uuidString)"
        let store = SessionStore.shared
        let prompt = "You are a helpful assistant. You will be presented with a user prompt, and your job is to provide a short title for a task that will be created from that prompt. The title you generate will be shown in the UI to represent the prompt."
        await store.upsertCodexSession(
            sessionId: sessionId, name: "Project title", preview: "Working", cwd: "/tmp/project",
            phase: .processing, intervention: nil
        )
        await store.syncCodexThreadSnapshot(CodexThreadSnapshot(
            threadId: sessionId, name: "Project title", preview: #"{"title":"Project title"}"#,
            cwd: "/tmp/project", clientInfo: .codexApp(threadId: sessionId), intervention: nil,
            createdAt: Date(), updatedAt: Date(), phase: .waitingForInput, historyItems: [],
            conversationInfo: ConversationInfo(
                summary: "Project title", lastMessage: #"{"title":"Project title"}"#,
                lastMessageRole: "assistant", lastToolName: nil,
                firstUserMessage: prompt, lastUserMessageDate: Date()
            ),
            latestTurnId: nil, latestResponseText: #"{"title":"Project title"}"#,
            latestResponsePhase: "final", latestUserText: prompt
        ))
        let session = await store.session(for: sessionId)
        XCTAssertNil(session)
    }

    private func makeCodexEvent(
        sessionId: String,
        event: String,
        status: String,
        message: String? = nil,
        cwd: String = "/tmp/ping-island-codex-placeholder",
        threadSource: String? = nil,
        sessionFilePath: String? = nil
    ) -> HookEvent {
        HookEvent(
            sessionId: sessionId,
            cwd: cwd,
            event: event,
            status: status,
            provider: .codex,
            clientInfo: SessionClientInfo(
                kind: .codexCLI,
                profileID: "codex_cli",
                name: "Codex CLI",
                bundleIdentifier: "com.openai.codex",
                threadSource: threadSource,
                sessionFilePath: sessionFilePath
            ),
            pid: nil,
            tty: nil,
            tool: nil,
            toolInput: nil,
            toolUseId: nil,
            notificationType: nil,
            message: message
        )
    }
}
