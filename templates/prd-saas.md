# PRD Template — SaaS Platform

## Product Overview

**Product Name:** [Your SaaS Name]
**Description:** [What it does]
**Tech Stack:** [e.g., Next.js + Supabase + Stripe]
**Pricing Model:** [Free tier + paid plans]

## prd.json Format

```json
{
  "project": "MySaaS",
  "branchName": "ralph/saas-platform",
  "description": "SaaS platform with auth, billing, and dashboards",
  "userStories": [
    {
      "id": "US-001",
      "title": "Set up project with auth and database",
      "description": "Foundation: Next.js + Supabase + Tailwind",
      "acceptanceCriteria": [
        "Next.js app with App Router",
        "Supabase auth configured (email + OAuth)",
        "Database schema for users and organizations",
        "RLS policies for multi-tenant data isolation",
        "Protected dashboard route"
      ],
      "priority": 1,
      "passes": false,
      "notes": ""
    },
    {
      "id": "US-002",
      "title": "Implement Stripe billing integration",
      "description": "Subscription management with Stripe",
      "acceptanceCriteria": [
        "Stripe checkout session creation",
        "Webhook handler for subscription events",
        "Plans table synced with Stripe products",
        "User subscription status reflected in UI",
        "Billing portal link for self-service"
      ],
      "priority": 2,
      "passes": false,
      "notes": ""
    },
    {
      "id": "US-003",
      "title": "Build admin dashboard",
      "description": "Dashboard with analytics and user management",
      "acceptanceCriteria": [
        "Dashboard layout with sidebar navigation",
        "User count and subscription metrics",
        "Recent activity feed",
        "User management table with search",
        "Responsive design"
      ],
      "priority": 3,
      "passes": false,
      "notes": ""
    }
  ]
}
```
