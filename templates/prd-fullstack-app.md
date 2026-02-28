# PRD Template — Fullstack Web Application

## Instructions

Fill in the sections below and save as `prd.json` using the format at the bottom.
Ralph+ will execute each story autonomously.

---

## Product Overview

**Product Name:** [Your App Name]
**Description:** [Brief description of the application]
**Tech Stack:** [e.g., Next.js 14 + Supabase + Tailwind CSS]
**Target Users:** [Who will use this]

## Core Features

### Feature 1: [Name]
- Description: [What it does]
- User Stories:
  1. [As a user, I want to... so that...]
  2. [As a user, I want to... so that...]

### Feature 2: [Name]
- Description: [What it does]
- User Stories:
  1. [As a user, I want to... so that...]

## Non-Functional Requirements

- Authentication: [e.g., Supabase Auth, NextAuth]
- Database: [e.g., PostgreSQL via Supabase]
- Styling: [e.g., Tailwind CSS, shadcn/ui]
- Deployment: [e.g., Vercel, Railway]
- Performance: [e.g., < 2s page load]

---

## prd.json Format

```json
{
  "project": "MyApp",
  "branchName": "ralph/feature-name",
  "description": "Brief description",
  "userStories": [
    {
      "id": "US-001",
      "title": "Set up project with Next.js + Supabase",
      "description": "Initialize the project with the chosen tech stack",
      "acceptanceCriteria": [
        "Next.js 14 app created with App Router",
        "Supabase client configured",
        "Tailwind CSS configured",
        "Development server runs without errors"
      ],
      "priority": 1,
      "passes": false,
      "notes": "Foundation story — all others depend on this"
    },
    {
      "id": "US-002",
      "title": "Implement authentication flow",
      "description": "Add sign up, sign in, and sign out functionality",
      "acceptanceCriteria": [
        "Sign up form with email/password",
        "Sign in form with email/password",
        "Sign out button in navigation",
        "Protected routes redirect to sign in",
        "Session persists across page refreshes"
      ],
      "priority": 2,
      "passes": false,
      "notes": ""
    }
  ]
}
```
