import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent"
import { Type } from "typebox"

const EFFORTS = ["off", "minimal", "low", "medium", "high", "xhigh", "max", "unknown"]
const label = /^[A-Za-z0-9_./:@+-]{1,128}$/
const isWorker = (ctx: ExtensionContext) => /<active_agent\s+name=/.test(ctx.getSystemPrompt())

export type TaskOutcomeReceipt = { taskId: string, outcome: "accepted" | "reworked" | "rejected", model: string, effort: string, checkArtifact: string }

// Coordinator-reported claim, not runtime proof; completion alone never implies acceptance.
export function validateReceipt(args: TaskOutcomeReceipt): TaskOutcomeReceipt {
  if (!["accepted", "reworked", "rejected"].includes(args.outcome)) throw new Error("outcome must be accepted, reworked or rejected.")
  for (const key of ["taskId", "model"] as const) if (!label.test(args[key])) throw new Error(`${key} must be 1-128 characters from A-Za-z0-9_./:@+-.`)
  if (!EFFORTS.includes(args.effort)) throw new Error(`effort must be one of ${EFFORTS.join(", ")}.`)
  if (!/^[^\s\0-\x1f\x7f]{1,300}$/.test(args.checkArtifact)) throw new Error("checkArtifact must be a path of at most 300 characters without whitespace or control characters.")
  return { taskId: args.taskId, outcome: args.outcome, model: args.model, effort: args.effort, checkArtifact: args.checkArtifact }
}

export default function (pi: ExtensionAPI) {
  pi.registerTool({
    name: "task_outcome",
    label: "Task outcome",
    description: "Coordinator-only: record the verified outcome of one task with the model and effort you dispatched it with and the path of the check artifact. Reported claim, not runtime proof.",
    parameters: Type.Object({
      taskId: Type.String({ maxLength: 128 }),
      outcome: Type.Union([Type.Literal("accepted"), Type.Literal("reworked"), Type.Literal("rejected")]),
      model: Type.String({ maxLength: 128 }),
      effort: Type.String({ maxLength: 16 }),
      checkArtifact: Type.String({ maxLength: 300 }),
    }),
    async execute(_id, args, _signal, _update, ctx) {
      if (isWorker(ctx)) throw new Error("Workers cannot record coordinator task outcomes.")
      const receipt = validateReceipt(args)
      pi.appendEntry("task-outcome-receipt", receipt)
      return { content: [{ type: "text", text: `Recorded ${receipt.outcome} for ${receipt.taskId}.` }], details: receipt }
    },
  })
}
