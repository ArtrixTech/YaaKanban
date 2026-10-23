import Foundation
import YaaCore

/// OpenCode and pi load TypeScript plugins from a directory. YaaKanban owns one file in each, which
/// forwards events to `yaak hook <agent> <event>` in the "yaak" schema (see `Normalizer.yaakSchema`).
protocol PluginFileIntegration: Integration {
    func file(_ home: URL) -> URL
    func detectDir(_ home: URL) -> URL
    func source(yaak: String) -> String
}

extension PluginFileIntegration {
    public func isDetected(home: URL) -> Bool { FileManager.default.fileExists(atPath: detectDir(home).path) }

    public func isInstalled(home: URL) -> Bool {
        Installer.read(file(home))?.contains(PluginSource.marker) ?? false
    }

    public func plan(install: Bool, home: URL, yaak: String) throws -> [FileChange] {
        let url = file(home)
        let before = Installer.read(url)
        if let before, !before.contains(PluginSource.marker) {
            throw IntegrationError.refused("\(url.path) exists and is not managed by YaaKanban")
        }
        let after = install ? source(yaak: yaak) : nil
        return before == after ? [] : [FileChange(path: url, before: before, after: after)]
    }
}

enum PluginSource {
    static let markerText = "managed by YaaKanban"
    static let marker = "// \(markerText)"

    static func jsString(_ s: String) -> String {
        let d = try! JSONSerialization.data(withJSONObject: [s], options: [.withoutEscapingSlashes])
        return String(String(decoding: d, as: UTF8.self).dropFirst().dropLast())
    }
}

public struct OpenCodeIntegration: PluginFileIntegration {
    public let agent = AgentKind.opencode
    public init() {}

    func detectDir(_ home: URL) -> URL { home.appendingPathComponent(".config/opencode") }
    func file(_ home: URL) -> URL { home.appendingPathComponent(".config/opencode/plugins/yaakanban.ts") }

    func source(yaak: String) -> String {
        """
        \(PluginSource.marker) — `yaak uninstall --agent opencode` removes this file.
        const YAAK = \(PluginSource.jsString(yaak))

        async function run(event: string, payload: any, wait: boolean): Promise<string> {
          try {
            const p = Bun.spawn([YAAK, "hook", "opencode", event], {
              stdin: "pipe", stdout: wait ? "pipe" : "ignore", stderr: "ignore",
              env: { ...process.env, YAAK_AGENT_PID: String(process.pid) },
            })
            p.stdin.write(JSON.stringify(payload))
            p.stdin.end()
            if (!wait) { await p.exited; return "" }
            return (await new Response(p.stdout).text()).trim()
          } catch { return "" }
        }

        // Events are delivered one at a time so the app sees them in order.
        let chain: Promise<unknown> = Promise.resolve()
        function send(event: string, payload: any, wait = false): Promise<string> {
          const body = { ...payload, ts: Date.now() }
          if (wait) return run(event, body, true)
          chain = chain.then(() => run(event, body, false))
          return Promise.resolve("")
        }

        export const YaaKanban = async ({ directory }: any) => {
          const cwd = directory
          const asking = new Set<string>()
          return {
            event: async ({ event }: any) => {
              const pr = event.properties ?? {}
              switch (event.type) {
                case "session.created": send("session_start", { session_id: pr.info?.id, cwd }); break
                case "session.idle": send("turn_end", { session_id: pr.sessionID, cwd }); break
                case "session.deleted": send("session_end", { session_id: pr.info?.id, cwd }); break
                case "permission.updated":
                  if (!asking.has(pr.id)) send("needs_input", { session_id: pr.sessionID, cwd, message: pr.title })
                  break
                case "permission.replied": send("input_answered", { session_id: pr.sessionID, cwd }); break
              }
            },
            "chat.message": async (input: any, output: any) => {
              const text = (output.parts ?? []).filter((p: any) => p.type === "text").map((p: any) => p.text).join("\\n")
              send("prompt", { session_id: input.sessionID, cwd, prompt: text })
            },
            "tool.execute.before": async (input: any, output: any) => {
              send("tool_start", { session_id: input.sessionID, cwd, id: input.callID, tool: input.tool, input: output.args })
            },
            "tool.execute.after": async (input: any, output: any) => {
              send("tool_end", { session_id: input.sessionID, cwd, id: input.callID, tool: input.tool,
                                 output: String(output?.output ?? "").slice(0, 2048) })
            },
            "permission.ask": async (input: any, output: any) => {
              asking.add(input.id)
              try {
                const r = await send("permission", { session_id: input.sessionID, cwd, id: input.callID ?? input.id,
                                                     tool: input.type, title: input.title, input: input.metadata }, true)
                if (r === "allow" || r === "deny") output.status = r
              } finally { asking.delete(input.id) }
            },
          }
        }

        """
    }
}

public struct PiIntegration: PluginFileIntegration {
    public let agent = AgentKind.pi
    public init() {}

    func detectDir(_ home: URL) -> URL { home.appendingPathComponent(".pi/agent") }
    func file(_ home: URL) -> URL { home.appendingPathComponent(".pi/agent/extensions/yaakanban.ts") }

    func source(yaak: String) -> String {
        """
        \(PluginSource.marker) — `yaak uninstall --agent pi` removes this file.
        import { spawn } from "node:child_process"
        import { existsSync } from "node:fs"
        import { homedir } from "node:os"
        import { join } from "node:path"

        const YAAK = \(PluginSource.jsString(yaak))

        function run(event: string, body: any): Promise<void> {
          return new Promise((resolve) => {
            try {
              const p = spawn(YAAK, ["hook", "pi", event], {
                stdio: ["pipe", "ignore", "ignore"],
                env: { ...process.env, YAAK_AGENT_PID: String(process.pid) },
              })
              p.on("error", () => resolve())
              p.on("close", () => resolve())
              p.stdin.on("error", () => {})
              p.stdin.end(JSON.stringify(body))
            } catch { resolve() }
          })
        }

        // Events are delivered one at a time so the app sees them in order.
        let chain: Promise<void> = Promise.resolve()
        function send(event: string, payload: any) {
          const body = { ...payload, ts: Date.now() }
          chain = chain.then(() => run(event, body))
        }

        // pi names a session only through /name. Unless the user turned it off in YaaKanban's
        // settings (which leaves this file behind), name an unnamed session after its first prompt.
        const yaakHome = process.env.YAAK_HOME ?? join(homedir(), "Library/Application Support/YaaKanban")
        const autoTitleOff = join(yaakHome, "\(Paths.piAutoTitleOffName)")
        const TITLE_PROMPT = "Write a title of at most 6 words for a coding session that starts with the request below. " +
          "Use the request's language. Reply with the title only, no quotes or punctuation at the end."

        async function autoTitle(pi: any, ctx: any, prompt: string) {
          try {
            if (existsSync(autoTitleOff) || !ctx.model || pi.getSessionName()) return
            const signal = AbortSignal.timeout(30000)
            const reply = await ctx.modelRegistry.streamSimple(ctx.model, {
              systemPrompt: TITLE_PROMPT,
              messages: [{ role: "user", content: prompt.slice(0, 2000), timestamp: Date.now() }],
            }, { maxTokens: 64, signal }).result()
            if (reply?.stopReason === "error" || reply?.stopReason === "aborted") return
            const text = (reply?.content ?? []).filter((b: any) => b?.type === "text").map((b: any) => b.text).join("")
            const title = text.split("\\n").map((l: string) => l.trim()).find(Boolean)?.replace(/^["'“”「『]+|["'“”」』。.]+$/g, "")
            // The user may have named it with /name meanwhile.
            if (title && !pi.getSessionName()) pi.setSessionName(title.slice(0, 80))
          } catch {}
        }

        function lastText(messages: any[]): string | undefined {
          for (let i = (messages?.length ?? 0) - 1; i >= 0; i--) {
            const m = messages[i]
            if (m?.role !== "assistant") continue
            const c = m.content
            if (typeof c === "string") return c
            const t = (c ?? []).filter((b: any) => b?.type === "text").map((b: any) => b.text).join("\\n")
            if (t) return t
          }
        }

        export default function (pi: any) {
          let last: string | undefined
          const base = (ctx: any) => {
            const file = ctx?.sessionManager?.getSessionFile?.()
            return { session_id: file ?? ctx?.sessionManager?.getSessionId?.() ?? String(process.pid),
                     transcript_path: file, cwd: process.cwd() }
          }
          let titled = false
          const sendTitle = (ctx: any, name: string | undefined) => send("title", { ...base(ctx), title: name ?? null })
          pi.on("session_start", async (_e: any, ctx: any) => {
            send("session_start", base(ctx))
            titled = !!pi.getSessionName()
            if (titled) sendTitle(ctx, pi.getSessionName())
          })
          pi.on("session_info_changed", async (e: any, ctx: any) => { titled = true; sendTitle(ctx, e.name) })
          pi.on("input", async (e: any, ctx: any) => {
            send("prompt", { ...base(ctx), prompt: e.text })
            // Titled once per session, from the first prompt the user typed; never awaited.
            if (!titled && e.source !== "extension" && e.text?.trim() && !e.text.startsWith("/")) {
              titled = true
              void autoTitle(pi, ctx, e.text)
            }
            return { action: "continue" }
          })
          pi.on("tool_execution_start", async (e: any, ctx: any) =>
            send("tool_start", { ...base(ctx), id: e.toolCallId, tool: e.toolName, input: e.args }))
          pi.on("tool_execution_end", async (e: any, ctx: any) =>
            send("tool_end", { ...base(ctx), id: e.toolCallId, tool: e.toolName, is_error: e.isError,
                               output: (typeof e.result === "string" ? e.result : JSON.stringify(e.result ?? "")).slice(0, 2048) }))
          pi.on("ui_prompt_start", async (e: any, ctx: any) =>
            send("needs_input", { ...base(ctx), message: e.title ?? `Waiting for ${e.kind}` }))
          pi.on("ui_prompt_end", async (_e: any, ctx: any) => send("input_answered", base(ctx)))
          pi.on("agent_end", async (e: any) => { last = lastText(e.messages) })
          pi.on("agent_settled", async (_e: any, ctx: any) => { send("turn_end", { ...base(ctx), message: last }); last = undefined })
          pi.on("session_shutdown", async (_e: any, ctx: any) => send("session_end", base(ctx)))
        }

        """
    }
}

/// oh-my-pi: a pi fork with its own home (`~/.omp/agent`) and event set. It has no `ui_prompt_*`,
/// `agent_settled` or `session_info_changed`; a turn ends at the `agent_end` that will not continue,
/// and the tool-approval events stand in for prompts. Extensions are rebound to sub-agent sessions,
/// whose events are skipped.
public struct OmpIntegration: PluginFileIntegration {
    public let agent = AgentKind.omp
    public init() {}
    public var postInstallNote: String? { "omp 的扩展目录按默认的 ~/.omp/agent；PI_CODING_AGENT_DIR 或 profile 不会跟随。" }

    func detectDir(_ home: URL) -> URL { home.appendingPathComponent(".omp") }
    func file(_ home: URL) -> URL { home.appendingPathComponent(".omp/agent/extensions/yaakanban.ts") }

    func source(yaak: String) -> String {
        """
        \(PluginSource.marker) — `yaak uninstall --agent omp` removes this file.
        import { spawn } from "node:child_process"

        const YAAK = \(PluginSource.jsString(yaak))

        function run(event: string, body: any): Promise<void> {
          return new Promise((resolve) => {
            try {
              const p = spawn(YAAK, ["hook", "omp", event], {
                stdio: ["pipe", "ignore", "ignore"],
                env: { ...process.env, YAAK_AGENT_PID: String(process.pid) },
              })
              p.on("error", () => resolve())
              p.on("close", () => resolve())
              p.stdin.on("error", () => {})
              p.stdin.end(JSON.stringify(body))
            } catch { resolve() }
          })
        }

        // Events are delivered one at a time so the app sees them in order.
        let chain: Promise<void> = Promise.resolve()
        function send(event: string, payload: any) {
          const body = { ...payload, ts: Date.now() }
          chain = chain.then(() => run(event, body))
        }

        function lastText(messages: any[]): string | undefined {
          for (let i = (messages?.length ?? 0) - 1; i >= 0; i--) {
            const m = messages[i]
            if (m?.role !== "assistant") continue
            const c = m.content
            if (typeof c === "string") return c
            const t = (c ?? []).filter((b: any) => b?.type === "text").map((b: any) => b.text).join("\\n")
            if (t) return t
          }
        }

        export default function (pi: any) {
          const sub = (ctx: any) => ctx?.agent?.kind === "sub"
          const base = (ctx: any) => {
            const file = ctx?.sessionManager?.getSessionFile?.()
            return { session_id: file ?? ctx?.sessionManager?.getSessionId?.() ?? String(process.pid),
                     transcript_path: file, cwd: ctx?.sessionManager?.getCwd?.() ?? process.cwd() }
          }
          const on = (name: string, f: (e: any, ctx: any) => void) =>
            pi.on(name, async (e: any, ctx: any) => { try { if (!sub(ctx)) f(e, ctx) } catch {} })
          on("session_start", (_e, ctx) => {
            send("session_start", base(ctx))
            const name = pi.getSessionName?.()
            if (name) send("title", { ...base(ctx), title: name })
          })
          on("input", (e, ctx) => send("prompt", { ...base(ctx), prompt: e.text }))
          on("tool_execution_start", (e, ctx) => {
            send("tool_start", { ...base(ctx), id: e.toolCallId, tool: e.toolName, input: e.args })
            // omp's question tool; answering it ends the call, which clears the attention.
            if (e.toolName === "ask") send("needs_input", { ...base(ctx), message: "Waiting for your answer" })
          })
          on("tool_execution_end", (e, ctx) =>
            send("tool_end", { ...base(ctx), id: e.toolCallId, tool: e.toolName, is_error: e.isError,
                               output: (typeof e.result === "string" ? e.result : JSON.stringify(e.result ?? "")).slice(0, 2048) }))
          on("tool_approval_requested", (e, ctx) =>
            send("needs_input", { ...base(ctx), message: e.reason ?? `omp wants to run ${e.toolName}` }))
          on("tool_approval_resolved", (_e, ctx) => send("input_answered", base(ctx)))
          on("agent_end", (e, ctx) => {
            if (e.willContinue) return
            send("turn_end", { ...base(ctx), message: lastText(e.messages) })
          })
          on("session_shutdown", (_e, ctx) => send("session_end", base(ctx)))
        }

        """
    }
}
