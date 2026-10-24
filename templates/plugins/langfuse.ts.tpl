import { Plugin } from "@opencode/plugin"
import { randomBytes } from "node:crypto"
import { readFile } from "node:fs/promises"
import { join } from "node:path"

type LangfuseSecrets = {
  public_key: string
  secret_key: string
}

type SessionInfo = {
  sessionId: string
  parentId: string | null
  traceId: string
  spanId: string
  agent: string | null
  provider: string | null
  model: string | null
  title: string | null
  startedNs: bigint
}

type GenerationInfo = {
  sessionId: string
  messageId: string
  spanId: string
  startedNs: bigint
  agent: string | null
  provider: string | null
  model: string | null
  variant: string | null
}

const LANGFUSE_ENABLED =
  "${LANGFUSE_ENABLED}" === "1"

const LANGFUSE_BASE_URL =
  "${LANGFUSE_BASE_URL}"

const sessions =
  new Map<string, SessionInfo>()

const generations =
  new Map<string, GenerationInfo>()

function randomHex(
  bytes: number,
): string {
  return randomBytes(bytes).toString("hex")
}

function attribute(
  key: string,
  value: string,
) {
  return {
    key,
    value: {
      stringValue: value,
    },
  }
}

function generationKey(
  sessionId: string,
  messageId: string,
): string {
  return `${sessionId}:${messageId}`
}

function usageDetails(
  tokens: any,
) {
  return {
    input: tokens?.input ?? 0,
    output: tokens?.output ?? 0,
    reasoning: tokens?.reasoning ?? 0,
    cache_read_input_tokens:
      tokens?.cache?.read ?? 0,
    cache_write_input_tokens:
      tokens?.cache?.write ?? 0,
  }
}

function basicAuth(
  publicKey: string,
  secretKey: string,
): string {
  return (
    "Basic " +
    Buffer
      .from(
        `${publicKey}:${secretKey}`,
      )
      .toString("base64")
  )
}

async function loadSecrets(
  directory: string,
): Promise<LangfuseSecrets> {
  const path = join(
    directory,
    "config",
    "langfuse.secrets.json",
  )

  let text: string

  try {
    text = await readFile(
      path,
      "utf8",
    )
  } catch (error) {
    throw new Error(
      `Cannot read Langfuse secrets file: ${path}`,
      {
        cause: error,
      },
    )
  }

  let value: unknown

  try {
    value = JSON.parse(text)
  } catch (error) {
    throw new Error(
      `Invalid JSON in Langfuse secrets file: ${path}`,
      {
        cause: error,
      },
    )
  }

  if (
    typeof value !== "object" ||
    value === null
  ) {
    throw new Error(
      `Invalid Langfuse secrets file: ${path}`,
    )
  }

  const secrets =
    value as Partial<LangfuseSecrets>

  if (
    typeof secrets.public_key !== "string" ||
    secrets.public_key.length === 0 ||
    typeof secrets.secret_key !== "string" ||
    secrets.secret_key.length === 0
  ) {
    throw new Error(
      `Langfuse secrets file must contain ` +
      `non-empty public_key and secret_key: ${path}`,
    )
  }

  return {
    public_key: secrets.public_key,
    secret_key: secrets.secret_key,
  }
}

async function sendSpans(
  baseUrl: string,
  publicKey: string,
  secretKey: string,
  spans: any[],
): Promise<void> {
  if (spans.length === 0) {
    return
  }

  const endpoint =
    `${baseUrl.replace(/\/+$/, "")}` +
    `/api/public/otel/v1/traces`

  const response = await fetch(
    endpoint,
    {
      method: "POST",

      headers: {
        Authorization:
          basicAuth(
            publicKey,
            secretKey,
          ),

        "Content-Type":
          "application/json",

        "x-langfuse-ingestion-version":
          "4",
      },

      body: JSON.stringify({
        resourceSpans: [
          {
            resource: {
              attributes: [
                attribute(
                  "service.name",
                  "adr-tooling-opencode",
                ),
              ],
            },

            scopeSpans: [
              {
                scope: {
                  name:
                    "adr-tooling-opencode",

                  version:
                    "1",
                },

                spans,
              },
            ],
          },
        ],
      }),
    },
  )

  if (!response.ok) {
    const body =
      await response.text()

    throw new Error(
      `Langfuse OTEL ingestion failed: ` +
      `${response.status} ${body}`,
    )
  }
}

function traceAttributes(
  session: SessionInfo,
) {
  return [
    attribute(
      "langfuse.trace.name",
      session.title ??
        `opencode:${session.agent ?? "session"}`,
    ),

    attribute(
      "langfuse.session.id",
      session.sessionId,
    ),

    attribute(
      "langfuse.trace.metadata.opencode_session_id",
      session.sessionId,
    ),

    attribute(
      "langfuse.trace.metadata.agent",
      session.agent ?? "unknown",
    ),

    attribute(
      "langfuse.trace.metadata.provider",
      session.provider ?? "unknown",
    ),

    attribute(
      "langfuse.trace.metadata.model",
      session.model ?? "unknown",
    ),
  ]
}

function eventTimeNs(
  event: any,
): bigint {
  return (
    BigInt(event.created) *
    1_000_000n
  )
}

export default Plugin.define({
  id: "adr-tooling-langfuse",

  setup(ctx) {
    if (!LANGFUSE_ENABLED) {
      return
    }

    if (!LANGFUSE_BASE_URL) {
      throw new Error(
        "Langfuse enabled but LANGFUSE_BASE_URL is empty",
      )
    }

    const controller =
      new AbortController()

    void (async () => {
      const secrets =
        await loadSecrets(
          ctx.location.directory,
        )

      const publicKey =
        secrets.public_key

      const secretKey =
        secrets.secret_key

      for await (
        const event of
          ctx.event.subscribe({
            signal:
              controller.signal,
          })
      ) {
        const data =
          event.data ?? {}

        switch (event.type) {
          case "session.created": {
            const sessionId =
              data.sessionID

            if (!sessionId) {
              break
            }

            let traceId: string

            if (data.parentID) {
              const parent =
                sessions.get(
                  data.parentID,
                )

              traceId =
                parent?.traceId ??
                randomHex(16)
            } else {
              traceId =
                randomHex(16)
            }

            sessions.set(
              sessionId,
              {
                sessionId,

                parentId:
                  data.parentID ??
                  null,

                traceId,

                spanId:
                  randomHex(8),

                agent:
                  data.agent ??
                  null,

                provider:
                  data.model
                    ?.providerID ??
                  null,

                model:
                  data.model?.id ??
                  null,

                title:
                  data.title ??
                  null,

                startedNs:
                  eventTimeNs(
                    event,
                  ),
              },
            )

            break
          }

          case "session.agent.selected": {
            const session =
              sessions.get(
                data.sessionID,
              )

            if (!session) {
              break
            }

            session.agent =
              data.agent ??
              session.agent

            break
          }

          case "session.model.selected": {
            const session =
              sessions.get(
                data.sessionID,
              )

            if (!session) {
              break
            }

            session.provider =
              data.model?.providerID ??
              session.provider

            session.model =
              data.model?.id ??
              session.model

            break
          }

          case "session.renamed": {
            const session =
              sessions.get(
                data.sessionID,
              )

            if (!session) {
              break
            }

            session.title =
              data.title ??
              session.title

            break
          }

          case "session.step.started": {
            const session =
              sessions.get(
                data.sessionID,
              )

            if (!session) {
              break
            }

            const messageId =
              data.assistantMessageID

            if (!messageId) {
              break
            }

            const key =
              generationKey(
                data.sessionID,
                messageId,
              )

            generations.set(
              key,
              {
                sessionId:
                  data.sessionID,

                messageId,

                spanId:
                  randomHex(8),

                startedNs:
                  BigInt(
                    data.started ??
                    event.created,
                  ) *
                  1_000_000n,

                agent:
                  data.agent ??
                  session.agent,

                provider:
                  data.model
                    ?.providerID ??
                  session.provider,

                model:
                  data.model?.id ??
                  session.model,

                variant:
                  data.model?.variant ??
                  null,
              },
            )

            break
          }

          case "session.step.ended": {
            const session =
              sessions.get(
                data.sessionID,
              )

            if (!session) {
              break
            }

            const messageId =
              data.assistantMessageID

            if (!messageId) {
              break
            }

            const key =
              generationKey(
                data.sessionID,
                messageId,
              )

            const generation =
              generations.get(key)

            if (!generation) {
              break
            }

            const attributes = [
              ...traceAttributes(
                session,
              ),

              attribute(
                "langfuse.observation.type",
                "generation",
              ),

              attribute(
                "langfuse.observation.model.name",
                generation.model ??
                  "unknown",
              ),

              attribute(
                "langfuse.observation.metadata.agent",
                generation.agent ??
                  "unknown",
              ),

              attribute(
                "langfuse.observation.metadata.provider",
                generation.provider ??
                  "unknown",
              ),

              attribute(
                "langfuse.observation.metadata.variant",
                generation.variant ??
                  "default",
              ),

              attribute(
                "langfuse.observation.metadata.finish",
                data.finish ??
                  "unknown",
              ),

              attribute(
                "langfuse.observation.usage_details",
                JSON.stringify(
                  usageDetails(
                    data.tokens,
                  ),
                ),
              ),
            ]

            if (
              typeof data.cost ===
                "number" &&
              data.cost > 0
            ) {
              attributes.push(
                attribute(
                  "langfuse.observation.cost_details",
                  JSON.stringify({
                    total:
                      data.cost,
                  }),
                ),
              )
            }

            await sendSpans(
              LANGFUSE_BASE_URL,
              publicKey,
              secretKey,
              [
                {
                  traceId:
                    session.traceId,

                  spanId:
                    generation.spanId,

                  parentSpanId:
                    session.spanId,

                  name:
                    `${
                      generation.agent ??
                      "agent"
                    } generation`,

                  startTimeUnixNano:
                    generation
                      .startedNs
                      .toString(),

                  endTimeUnixNano:
                    eventTimeNs(
                      event,
                    ).toString(),

                  attributes,
                },
              ],
            )

            generations.delete(
              key,
            )

            break
          }

          case "session.execution.succeeded": {
            const session =
              sessions.get(
                data.sessionID,
              )

            if (!session) {
              break
            }

            const parentSpanId =
              session.parentId
                ? sessions.get(
                    session.parentId,
                  )?.spanId
                : undefined

            const span: any = {
              traceId:
                session.traceId,

              spanId:
                session.spanId,

              name:
                session.agent ??
                "opencode-session",

              startTimeUnixNano:
                session.startedNs
                  .toString(),

              endTimeUnixNano:
                eventTimeNs(
                  event,
                ).toString(),

              attributes: [
                ...traceAttributes(
                  session,
                ),

                attribute(
                  "langfuse.observation.type",
                  "agent",
                ),

                attribute(
                  "langfuse.observation.metadata.opencode_parent_id",
                  session.parentId ??
                    "",
                ),
              ],
            }

            if (parentSpanId) {
              span.parentSpanId =
                parentSpanId
            }

            await sendSpans(
              LANGFUSE_BASE_URL,
              publicKey,
              secretKey,
              [span],
            )

            break
          }

          case "session.execution.failed":
          case "session.error": {
            const session =
              sessions.get(
                data.sessionID,
              )

            if (!session) {
              break
            }

            const parentSpanId =
              session.parentId
                ? sessions.get(
                    session.parentId,
                  )?.spanId
                : undefined

            const span: any = {
              traceId:
                session.traceId,

              spanId:
                session.spanId,

              name:
                session.agent ??
                "opencode-session",

              startTimeUnixNano:
                session.startedNs
                  .toString(),

              endTimeUnixNano:
                eventTimeNs(
                  event,
                ).toString(),

              status: {
                code: 2,
                message:
                  "OpenCode session failed",
              },

              attributes: [
                ...traceAttributes(
                  session,
                ),

                attribute(
                  "langfuse.observation.type",
                  "agent",
                ),

                attribute(
                  "langfuse.observation.level",
                  "ERROR",
                ),

                attribute(
                  "langfuse.observation.status_message",
                  "OpenCode session failed",
                ),

                attribute(
                  "langfuse.observation.metadata.opencode_parent_id",
                  session.parentId ??
                    "",
                ),
              ],
            }

            if (parentSpanId) {
              span.parentSpanId =
                parentSpanId
            }

            await sendSpans(
              LANGFUSE_BASE_URL,
              publicKey,
              secretKey,
              [span],
            )

            break
          }
        }
      }
    })().catch((error) => {
      console.error(
        "[adr-tooling-langfuse]",
        error,
      )
    })

    return () =>
      controller.abort()
  },
})