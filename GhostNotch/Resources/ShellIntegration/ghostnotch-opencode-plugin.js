// GHOSTNOTCH_MANAGED_HOOK=1
// OpenCode plugin that forwards session activity to GhostNotch's bundled state helper.

import { spawn } from "node:child_process"
import { access } from "node:fs/promises"
import { constants } from "node:fs"
import path from "node:path"

const agentName = "opencode"
const helperName = "ghostnotch-agent-hook"

function stateForEvent(event) {
  switch (event.type) {
    case "session.status":
      return stateForSessionStatus(event.properties?.status)
    case "session.idle":
    case "session.error":
      return "idle"
    case "permission.asked":
    case "permission.updated":
    case "question.asked":
      return "attention"
    case "permission.replied":
    case "question.replied":
    case "question.rejected":
      return "working"
    default:
      return null
  }
}

function stateForSessionStatus(status) {
  switch (status?.type) {
    case "busy":
    case "retry":
      return "working"
    case "idle":
      return "idle"
    default:
      return null
  }
}

async function writeGhostNotchState(event, state) {
  const resourcesDirectory = process.env.GHOSTNOTCH_RESOURCES_DIR
  const stateFile = process.env.GHOSTNOTCH_AGENT_STATE_FILE
  if (!resourcesDirectory || !stateFile) {
    return
  }

  const helperPath = path.join(resourcesDirectory, helperName)
  try {
    await access(helperPath, constants.X_OK)
  } catch {
    return
  }

  await new Promise((resolve) => {
    const child = spawn(
      helperPath,
      ["--agent", agentName, "--event", event.type, "--state", state],
      {
        env: process.env,
        stdio: ["pipe", "ignore", "ignore"],
      }
    )

    child.on("error", resolve)
    child.on("close", resolve)
    child.stdin.on("error", () => {})
    child.stdin.end(JSON.stringify({
      type: event.type,
      properties: event.properties ?? {},
    }))
  })
}

export const GhostNotchAgentIndicator = async () => {
  await writeGhostNotchState({ type: "PluginStart", properties: {} }, "idle")

  return {
    event: async ({ event }) => {
      const state = stateForEvent(event)
      if (!state) {
        return
      }

      await writeGhostNotchState(event, state)
    },
  }
}
