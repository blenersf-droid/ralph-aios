# PRD Template — Chrome Extension

## Product Overview

**Extension Name:** [Your Extension Name]
**Description:** [What it does]
**Manifest Version:** V3
**Permissions:** [e.g., activeTab, storage, tabs]

## prd.json Format

```json
{
  "project": "MyExtension",
  "branchName": "ralph/chrome-extension",
  "description": "Chrome extension for automation",
  "userStories": [
    {
      "id": "US-001",
      "title": "Set up Manifest V3 extension structure",
      "description": "Create the base Chrome extension with popup and background script",
      "acceptanceCriteria": [
        "manifest.json with V3 format",
        "Popup HTML with basic UI",
        "Background service worker registered",
        "Extension loads in chrome://extensions without errors",
        "Icon set configured (16, 32, 48, 128)"
      ],
      "priority": 1,
      "passes": false,
      "notes": ""
    },
    {
      "id": "US-002",
      "title": "Implement content script injection",
      "description": "Inject content script into target pages",
      "acceptanceCriteria": [
        "Content script matches target URLs",
        "Script injects successfully on page load",
        "Message passing between content script and popup works",
        "Content script has access to page DOM"
      ],
      "priority": 2,
      "passes": false,
      "notes": ""
    }
  ]
}
```
