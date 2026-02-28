# PRD Template — API / Microservice

## Product Overview

**Service Name:** [Your Service Name]
**Description:** [What this API does]
**Tech Stack:** [e.g., Node.js + Express + PostgreSQL]
**API Style:** [REST | GraphQL | tRPC]

## Endpoints

### Resource 1: [Name]
- `GET /api/v1/resource` — List all
- `GET /api/v1/resource/:id` — Get one
- `POST /api/v1/resource` — Create
- `PUT /api/v1/resource/:id` — Update
- `DELETE /api/v1/resource/:id` — Delete

## prd.json Format

```json
{
  "project": "MyAPI",
  "branchName": "ralph/api-service",
  "description": "REST API service",
  "userStories": [
    {
      "id": "US-001",
      "title": "Set up Express server with TypeScript",
      "description": "Initialize API project with proper structure",
      "acceptanceCriteria": [
        "Express server running on port 3000",
        "TypeScript configured with strict mode",
        "Health check endpoint: GET /health returns 200",
        "Error handling middleware configured",
        "CORS configured"
      ],
      "priority": 1,
      "passes": false,
      "notes": ""
    },
    {
      "id": "US-002",
      "title": "Set up database connection and migrations",
      "description": "Configure database with migration system",
      "acceptanceCriteria": [
        "Database connection pool configured",
        "Migration system set up",
        "Initial migration creates base tables",
        "Seed data script available"
      ],
      "priority": 2,
      "passes": false,
      "notes": ""
    }
  ]
}
```
