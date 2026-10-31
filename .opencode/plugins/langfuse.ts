import { Plugin } from "@opencode/plugin"
import { Buffer } from "node:buffer"
import { randomBytes } from "node:crypto"
import { readFile } from "node:fs/promises"
import { join } from "node:path"

const ENABLED = "1" === "1"
const BASE_URL = "http://localhost:3000".replace(/\/$/, "")
const SECRETS_FILE = "config/langfuse.secrets.json"

type SessionState = {
  traceId: string
  spanId: string
  parentSpanId?: string

  langfuseSessionId: string

  agent?: string
  model?: string

  input?: string
  output?: string

  started: number
}

type StepState = {
  traceId: string
  spanId: string
  parentSpanId: string

  sessionId: string
  langfuseSessionId: string
  assistantMessageId: string

  agent?: string
  model?: string

  input?: string

  started: number
}

type ToolState = {
  traceId: string
  spanId: string
  parentSpanId: string

  sessionId: string
  langfuseSessionId: string

  toolCallId: string
  tool: string

  input?: unknown

  started: number
}

type PromptRegistryEntry = {
  source?: string
  name?: string
  version?: number
  selector?: string
}

type PromptManifest = {
  profile?: string

  agents?: Record<
    string,
    PromptRegistryEntry
  >

  skills?: Record<
    string,
    PromptRegistryEntry
  >
}

const sessions = new Map<string, SessionState>()
const steps = new Map<string, StepState>()
const tools = new Map<string, ToolState>()

const assistantOutputs = new Map<string, string>()
const latestUserInput = new Map<string, string>()

const hex = (bytes: number) =>
  randomBytes(bytes).toString("hex")

const toNs = (milliseconds: number) =>
  String(
    BigInt(Math.trunc(milliseconds))
    * 1_000_000n,
  )

const stepKey = (
  sessionId: string,
  assistantMessageId: string,
) =>
  sessionId
  + ":"
  + assistantMessageId

const toolKey = (
  sessionId: string,
  toolCallId: string,
) =>
  sessionId
  + ":"
  + toolCallId

function isSemanticTool(
  name: unknown,
): name is string {
  if (typeof name !== "string") {
    return false
  }

  return (
    name === "skill"
    || name.startsWith("openflowkit_")
  )
}

function safeJson(
  value: unknown,
  maxLength = 8000,
): string | undefined {
  if (
    value === undefined
    || value === null
  ) {
    return undefined
  }

  let rendered: string

  try {
    rendered =
      typeof value === "string"
        ? value
        : JSON.stringify(value)
  } catch {
    rendered = String(value)
  }

  if (
    rendered.length
    <= maxLength
  ) {
    return rendered
  }

  return (
    rendered.slice(
      0,
      maxLength,
    )
    + "…"
  )
}

function skillName(
  input: unknown,
): string | undefined {
  if (
    !input
    || typeof input !== "object"
  ) {
    return undefined
  }

  const value =
    input as Record<string, unknown>

  for (
    const key
    of [
      "name",
      "skill",
      "id",
    ]
  ) {
    if (
      typeof value[key]
      === "string"
    ) {
      return value[key] as string
    }
  }

  return undefined
}

function semanticToolInput(
  tool: string,
  input: unknown,
): string | undefined {
  if (tool === "skill") {
    return (
      skillName(input)
      ?? safeJson(input)
    )
  }

  return safeJson(input)
}

function semanticToolOutput(
  tool: string,
  data: any,
): string | undefined {
  if (tool === "skill") {
    return "loaded"
  }

  return safeJson(
    data.content
    ?? data.result
    ?? data.metadata,
  )
}

async function credentials(
  directory: string,
) {
  const path = join(
    directory,
    SECRETS_FILE,
  )

  const data = JSON.parse(
    await readFile(
      path,
      "utf8",
    ),
  )

  if (
    !data.public_key
    || !data.secret_key
  ) {
    throw new Error(
      "Langfuse credentials missing in "
      + path,
    )
  }

  return data as {
    public_key: string
    secret_key: string
  }
}

async function promptManifest(
  directory: string,
): Promise<PromptManifest> {
  try {
    return JSON.parse(
      await readFile(
        join(
          directory,
          ".opencode/prompt-manifest.json",
        ),
        "utf8",
      ),
    )
  } catch {
    return {
      agents: {},
      skills: {},
    }
  }
}

function attributes(
  values: Record<
    string,
    unknown
  >,
) {
  return Object.entries(values)
    .filter(
      ([, value]) =>
        value !== undefined
        && value !== null,
    )
    .map(
      ([key, value]) => {
        if (
          typeof value
          === "number"
        ) {
          return {
            key,
            value: {
              doubleValue: value,
            },
          }
        }

        if (
          typeof value
          === "boolean"
        ) {
          return {
            key,
            value: {
              boolValue: value,
            },
          }
        }

        return {
          key,
          value: {
            stringValue:
              String(value),
          },
        }
      },
    )
}

function resourceSpans(
  spans: unknown[],
) {
  return [
    {
      resource: {
        attributes:
          attributes({
            "service.name":
              "opencode",

            "langfuse.environment":
              "default",
          }),
      },

      scopeSpans: [
        {
          scope: {
            name:
              "opencode-langfuse",
          },

          spans,
        },
      ],
    },
  ]
}

async function send(
  directory: string,
  spans: unknown[],
) {
  if (
    !ENABLED
    || spans.length === 0
  ) {
    return
  }

  const auth =
    await credentials(
      directory,
    )

  const encoded =
    Buffer.from(
      auth.public_key
      + ":"
      + auth.secret_key,
    ).toString("base64")

  const response =
    await fetch(
      BASE_URL
        + "/api/public/otel/v1/traces",

      {
        method: "POST",

        headers: {
          Authorization:
            "Basic "
            + encoded,

          "Content-Type":
            "application/json",

          "x-langfuse-ingestion-version":
            "4",
        },

        body:
          JSON.stringify({
            resourceSpans:
              resourceSpans(
                spans,
              ),
          }),
      },
    )

  if (!response.ok) {
    const body =
      await response.text()

    throw new Error(
      "Langfuse OTEL ingestion "
      + "failed: HTTP "
      + response.status
      + ": "
      + body,
    )
  }
}

async function emitTool(
  directory: string,
  state: ToolState,
  {
    status,
    output,
    error,
  }: {
    status: "completed" | "error"
    output?: string
    error?: string
  },
) {
    const manifest =
    await promptManifest(
      directory,
    )

  const loadedSkillName =
    state.tool === "skill"
      ? skillName(
          state.input,
        )
      : undefined

  const skillPrompt =
    loadedSkillName
      ? manifest.skills?.[
          loadedSkillName
        ]
      : undefined
  await send(
    directory,
    [
      {
        traceId:
          state.traceId,

        spanId:
          state.spanId,

        parentSpanId:
          state.parentSpanId,

        name:
          "tool:"
          + state.tool,

        kind: 1,

        startTimeUnixNano:
          toNs(
            state.started,
          ),

        endTimeUnixNano:
          toNs(
            Date.now(),
          ),

        attributes:
          attributes({
            "langfuse.observation.type":
              "tool",

            "langfuse.session.id":
              state.langfuseSessionId,

            "langfuse.observation.input":
              semanticToolInput(
                state.tool,
                state.input,
              ),

            "langfuse.observation.output":
              output,

            "langfuse.observation.level":
              status === "error"
                ? "ERROR"
                : "DEFAULT",

            "langfuse.observation.status_message":
              error,

            "opencode.tool.name":
              state.tool,

            "opencode.skill.source":
              skillPrompt?.source,

            "opencode.skill.prompt.name":
              skillPrompt?.name,

            "opencode.skill.prompt.version":
              skillPrompt?.version,

            "opencode.skill.prompt.selector":
              skillPrompt?.selector,

            "opencode.tool.call_id":
              state.toolCallId,

            "opencode.session.id":
              state.sessionId,

            "opencode.tool.status":
              status,

            "opencode.skill.name":
              state.tool
                === "skill"
                ? skillName(
                    state.input,
                  )
                : undefined,
          }),
      },
    ],
  )
}

async function handleEvent(
  ctx: any,
  event: any,
) {
  const directory =
    event.location
      ?.directory
    ?? ctx.location.directory

  const data =
    event.data ?? {}

  /*
   * User input.
   */
  if (
    event.type
    === "session.inbox.enqueued"
  ) {
    const item =
      data.item

    if (
      item?.type
        === "user"
      && typeof item.payload
        ?.text
        === "string"
    ) {
      const text =
        item.payload.text

      latestUserInput.set(
        data.sessionID,
        text,
      )

      const session =
        sessions.get(
          data.sessionID,
        )

      if (
        session
        && session.input
          === undefined
      ) {
        session.input =
          text
      }
    }

    return
  }

  /*
   * Assistant output.
   */
  if (
    event.type
    === "session.text.ended"
  ) {
    if (
      typeof data.text
        === "string"
      && data.assistantMessageID
    ) {
      assistantOutputs.set(
        stepKey(
          data.sessionID,
          data.assistantMessageID,
        ),
        data.text,
      )

      const session =
        sessions.get(
          data.sessionID,
        )

      if (session) {
        session.output =
          data.text
      }
    }

    return
  }

  /*
   * Session / agent.
   */
  if (
    event.type
    === "session.created"
  ) {
    const parent =
      data.parentID
        ? sessions.get(
            data.parentID,
          )
        : undefined

    sessions.set(
      data.sessionID,
      {
        traceId:
          parent?.traceId
          ?? hex(16),

        spanId:
          hex(8),

        parentSpanId:
          parent?.spanId,

        langfuseSessionId:
          parent
            ?.langfuseSessionId
          ?? data.sessionID,

        agent:
          data.agent,

        model:
          data.model?.id,

        started:
          Date.now(),
      },
    )

    return
  }

  if (
    event.type
    === "session.agent.selected"
  ) {
    const session =
      sessions.get(
        data.sessionID,
      )

    if (session) {
      session.agent =
        data.agent
    }

    return
  }

  if (
    event.type
    === "session.model.selected"
  ) {
    const session =
      sessions.get(
        data.sessionID,
      )

    if (session) {
      session.model =
        data.model?.id
    }

    return
  }

  /*
   * Semantic tool call begins.
   *
   * In OpenCode 2.1.4 this event contains
   * sessionID, assistantMessageID, id and name.
   */
  if (
    event.type
    === "session.tool.input.started"
  ) {
    const tool =
      data.name
      ?? data.tool

    if (
      !isSemanticTool(tool)
    ) {
      return
    }

    const session =
      sessions.get(
        data.sessionID,
      )

    if (!session) {
      return
    }

    tools.set(
      toolKey(
        data.sessionID,
        data.id,
      ),

      {
        traceId:
          session.traceId,

        spanId:
          hex(8),

        parentSpanId:
          session.spanId,

        sessionId:
          data.sessionID,

        langfuseSessionId:
          session.langfuseSessionId,

        toolCallId:
          data.id,

        tool,

        started:
          Date.now(),
      },
    )

    return
  }

  /*
   * Semantic tool input becomes available.
   */
  if (
    event.type
    === "session.tool.called"
  ) {
    const key =
      toolKey(
        data.sessionID,
        data.id,
      )

    let state =
      tools.get(key)

    if (!state) {
      const tool =
        data.name
        ?? data.tool

      if (
        !isSemanticTool(tool)
      ) {
        return
      }

      const session =
        sessions.get(
          data.sessionID,
        )

      if (!session) {
        return
      }

      state = {
        traceId:
          session.traceId,

        spanId:
          hex(8),

        parentSpanId:
          session.spanId,

        sessionId:
          data.sessionID,

        langfuseSessionId:
          session.langfuseSessionId,

        toolCallId:
          data.id,

        tool,

        started:
          Date.now(),
      }

      tools.set(
        key,
        state,
      )
    }

    state.input =
      data.input

    return
  }

  /*
   * Semantic tool completed.
   */
  if (
    event.type
    === "session.tool.success"
  ) {
    const key =
      toolKey(
        data.sessionID,
        data.id,
      )

    const state =
      tools.get(key)

    if (!state) {
      return
    }

    tools.delete(key)

    await emitTool(
      directory,
      state,
      {
        status:
          "completed",

        output:
          semanticToolOutput(
            state.tool,
            data,
          ),
      },
    )

    return
  }

  /*
   * Semantic tool failed.
   */
  if (
    event.type
    === "session.tool.failed"
  ) {
    const key =
      toolKey(
        data.sessionID,
        data.id,
      )

    const state =
      tools.get(key)

    if (!state) {
      return
    }

    tools.delete(key)

    await emitTool(
      directory,
      state,
      {
        status: "error",

        output:
          safeJson(
            data.content
            ?? data.result,
          ),

        error:
          data.error?.message
          ?? data.message
          ?? safeJson(
            data.error,
          ),
      },
    )

    return
  }

  /*
   * Generation begins.
   */
  if (
    event.type
    === "session.step.started"
  ) {
    const session =
      sessions.get(
        data.sessionID,
      )

    if (!session) {
      return
    }

    const input =
      latestUserInput.get(
        data.sessionID,
      )

    steps.set(
      stepKey(
        data.sessionID,
        data.assistantMessageID,
      ),

      {
        traceId:
          session.traceId,

        spanId:
          hex(8),

        parentSpanId:
          session.spanId,

        sessionId:
          data.sessionID,

        langfuseSessionId:
          session.langfuseSessionId,

        assistantMessageId:
          data.assistantMessageID,

        agent:
          data.agent
          ?? session.agent,

        model:
          data.model?.id
          ?? session.model,

        input,

        started:
          data.started
          ?? Date.now(),
      },
    )

    return
  }

  /*
   * Generation completes.
   */
  if (
    event.type
    === "session.step.ended"
  ) {
    const key =
      stepKey(
        data.sessionID,
        data.assistantMessageID,
      )

    const step =
      steps.get(key)

    if (!step) {
      return
    }

    steps.delete(key)

    const output =
      assistantOutputs.get(
        key,
      )

    assistantOutputs.delete(
      key,
    )

    const manifest =
      await promptManifest(
        directory,
      )

    const prompt =
      manifest.agents?.[
        step.agent ?? ""
      ]

    const spanAttributes:
      Record<string, unknown> = {
        "langfuse.observation.type":
          "generation",

        "langfuse.session.id":
          step.langfuseSessionId,

        "langfuse.observation.input":
          step.input,

        "langfuse.observation.output":
          output,

        "langfuse.observation.model.name":
          step.model,

        "gen_ai.request.model":
          step.model,

        "gen_ai.response.finish_reasons":
          data.finish,

        "gen_ai.usage.input_tokens":
          data.tokens?.input,

        "gen_ai.usage.output_tokens":
          data.tokens?.output,

        "gen_ai.usage.reasoning_tokens":
          data.tokens?.reasoning,

        "gen_ai.usage.cache_read_input_tokens":
          data.tokens
            ?.cache
            ?.read,

        "gen_ai.usage.cache_write_input_tokens":
          data.tokens
            ?.cache
            ?.write,

        "opencode.agent":
          step.agent,

        "opencode.profile":
          manifest.profile,

        "opencode.session.id":
          step.sessionId,
      }

    if (
      prompt?.source
      === "langfuse"
    ) {
      spanAttributes[
        "langfuse.observation.prompt.name"
      ] = prompt.name

      spanAttributes[
        "langfuse.observation.prompt.version"
      ] = prompt.version
    }

    await send(
      directory,
      [
        {
          traceId:
            step.traceId,

          spanId:
            step.spanId,

          parentSpanId:
            step.parentSpanId,

          name:
            "generation:"
            + (
              step.agent
              ?? "agent"
            ),

          kind: 1,

          startTimeUnixNano:
            toNs(
              step.started,
            ),

          endTimeUnixNano:
            toNs(
              Date.now(),
            ),

          attributes:
            attributes(
              spanAttributes,
            ),
        },
      ],
    )

    return
  }

  /*
   * Agent/subagent completes.
   */
  if (
    event.type
      ===
      "session.execution.succeeded"
    ||
    event.type
      ===
      "session.execution.failed"
  ) {
    const session =
      sessions.get(
        data.sessionID,
      )

    if (!session) {
      return
    }

    sessions.delete(
      data.sessionID,
    )

    latestUserInput.delete(
      data.sessionID,
    )

    /*
     * Drop unfinished semantic tool states
     * belonging to this OpenCode session.
     */
    for (
      const [
        key,
        state,
      ]
      of tools.entries()
    ) {
      if (
        state.sessionId
        === data.sessionID
      ) {
        tools.delete(key)
      }
    }

    const manifest =
      await promptManifest(
        directory,
      )

    await send(
      directory,
      [
        {
          traceId:
            session.traceId,

          spanId:
            session.spanId,

          parentSpanId:
            session.parentSpanId,

          name:
            session.parentSpanId
              ? "agent:"
                + (
                  session.agent
                  ?? "subagent"
                )
              : "agent:"
                + (
                  session.agent
                  ?? "primary"
                ),

          kind: 1,

          startTimeUnixNano:
            toNs(
              session.started,
            ),

          endTimeUnixNano:
            toNs(
              Date.now(),
            ),

          attributes:
            attributes({
              "langfuse.observation.type":
                "agent",

              "langfuse.session.id":
                session.langfuseSessionId,

              /*
               * Only the root agent names the
               * shared Langfuse trace.
               */
              "langfuse.trace.name":
                session.parentSpanId
                  ? undefined
                  : session.agent
                    ? "opencode:"
                      + session.agent
                    : "opencode",

              "langfuse.observation.input":
                session.input,

              "langfuse.observation.output":
                session.output,

              "opencode.agent":
                session.agent,

              "opencode.profile":
                manifest.profile,

              "opencode.session.id":
                data.sessionID,

              "gen_ai.request.model":
                session.model,

              "opencode.outcome":
                event.type.endsWith(
                  "succeeded",
                )
                  ? "succeeded"
                  : "failed",
            }),
        },
      ],
    )
  }
}

export default Plugin.define({
  id: "langfuse",

  setup(ctx) {
    if (!ENABLED) {
      return
    }

    const controller =
      new AbortController()

    void (async () => {
      for await (
        const event
        of ctx.event.subscribe({
          signal:
            controller.signal,
        })
      ) {
        try {
          await handleEvent(
            ctx,
            event,
          )
        } catch (error) {
          console.error(
            "langfuse plugin "
            + "event error:",
            error,
          )
        }
      }
    })().catch(
      (error) => {
        if (
          !controller.signal
            .aborted
        ) {
          console.error(
            "langfuse plugin "
            + "subscription error:",
            error,
          )
        }
      },
    )

    return () => {
      controller.abort()
    }
  },
})