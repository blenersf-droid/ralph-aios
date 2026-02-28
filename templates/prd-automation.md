# PRD Template — Automation Script / Tool

## Product Overview

**Tool Name:** [Your Tool Name]
**Description:** [What it automates]
**Language:** [Python | Bash | Node.js]
**Trigger:** [CLI | Cron | Webhook | Event]

## prd.json Format

```json
{
  "project": "MyAutomation",
  "branchName": "ralph/automation-tool",
  "description": "Automation script for [task]",
  "userStories": [
    {
      "id": "US-001",
      "title": "Set up project structure with CLI interface",
      "description": "Create the automation tool with proper CLI handling",
      "acceptanceCriteria": [
        "CLI entry point with argument parsing",
        "Help command with usage instructions",
        "Configuration file support (.env or config.yaml)",
        "Logging with configurable verbosity",
        "Dry-run mode for safe testing"
      ],
      "priority": 1,
      "passes": false,
      "notes": ""
    },
    {
      "id": "US-002",
      "title": "Implement core automation logic",
      "description": "The main automation workflow",
      "acceptanceCriteria": [
        "Core function implements the automation",
        "Error handling with retry logic",
        "Progress reporting during execution",
        "Idempotent operation (safe to re-run)",
        "Exit codes for success/failure/partial"
      ],
      "priority": 2,
      "passes": false,
      "notes": ""
    },
    {
      "id": "US-003",
      "title": "Add scheduling and notification",
      "description": "Automate execution and notify on completion",
      "acceptanceCriteria": [
        "Cron-compatible scheduling format",
        "Notification on success/failure (email, Slack, or webhook)",
        "Execution log with timestamps",
        "Lock file to prevent concurrent runs"
      ],
      "priority": 3,
      "passes": false,
      "notes": ""
    }
  ]
}
```
