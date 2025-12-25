# Dispatch System

Unified event dispatch system for workflows and agents. Handles event triggering, task queue management with warm runner pool, and webhook processing.

## Key Files

| File | Purpose |
|------|---------|
| `trigger.zig` | Event type definitions and triggering logic |
| `queue.zig` | Task queue with warm pool management |
| `webhook.zig` | Webhook processing and validation |

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Dispatch System                          │
│                                                             │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐  │
│  │   Trigger    │───▶│    Queue     │───▶│   Webhook    │  │
│  │              │    │              │    │              │  │
│  │ Event Types: │    │ Warm Pool:   │    │ Processing:  │  │
│  │              │    │              │    │              │  │
│  │ • push       │    │ • Standby    │    │ • GitHub     │  │
│  │ • pull_req   │    │ • Claimed    │    │ • Validation │  │
│  │ • issue      │    │ • Active     │    │ • Signature  │  │
│  │ • chat       │    │              │    │   verify     │  │
│  │ • schedule   │    │ Workloads:   │    │              │  │
│  │              │    │              │    │              │  │
│  │              │    │ • Workflow   │    │              │  │
│  │              │    │ • Agent      │    │              │  │
│  └──────────────┘    └──────────────┘    └──────────────┘  │
│                                                             │
│                 Assigns runners from warm pool              │
│                           │                                 │
│                           ▼                                 │
│                  Kubernetes (GKE)                           │
│                  Runner Pods                                │
└─────────────────────────────────────────────────────────────┘
```

## Event Flow

```
GitHub Webhook         API Request         Schedule
      │                    │                   │
      ├────────────────────┼───────────────────┤
      │                    │                   │
      ▼                    ▼                   ▼
┌──────────────────────────────────────────────────┐
│              Event Trigger                       │
│                                                  │
│  Determines event type and context               │
└────────────────────┬─────────────────────────────┘
                     │
                     ▼
┌──────────────────────────────────────────────────┐
│              Task Queue                          │
│                                                  │
│  1. Create workload entry                        │
│  2. Claim runner from warm pool                  │
│  3. Assign task to runner                        │
└────────────────────┬─────────────────────────────┘
                     │
                     ▼
              Runner Pod (K8s)
```

## Workload Types

| Type | Description | Pool Strategy |
|------|-------------|---------------|
| `workflow` | Workflow execution | Claim from warm pool |
| `agent` | Agent session | Claim from warm pool |

## Workload Status

| Status | Description |
|--------|-------------|
| `pending` | Waiting for runner assignment |
| `claimed` | Runner claimed, initializing |
| `running` | Executing |
| `completed` | Finished successfully |
| `failed` | Error during execution |
| `cancelled` | User-initiated cancel |
