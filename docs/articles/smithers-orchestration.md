# Plan Mode as Code with Smithers

Multi-agent AI workflows are hard.

- They are hard to trust. The more complex they get, the more ways they can fail.
- They are hard to monitor.
- Hard to debug.
- Hard to reason about.
- Making reusable code is usually a nightmare. Most workflows get written from scratch.

This is why I historically defaulted to simple [Ralph loops](https://ghuntley.com/ralph/). But what if we could build workflows out of smaller components using a declarative framework that is easy to monitor and evolve over time?

That is why I built **[Smithers](https://smithers.sh/)**.

Smithers is an open source, self-healing, easy to monitor Agent Orchestration framework. It follows in the steps of ralph offering minimal simple primitives needed to build simple loops that are easy to reason about. But it builds on top of React for reasons that will become clear as we show how well of an abstraction React is for these workflows.

- **Docs:** [https://smithers.sh](https://smithers.sh/)
- **Repo:** https://github.com/evmts/smithers
- **Example workflow:** https://github.com/evmts/agent/scripts/

------

## Hello World (Smithers)

```ts
import { createSmithers, Task, Ralph } from "smithers-orchestrator";
import { agent } from "ai";
import { anthropic } from "@ai-sdk/anthropic";
import { z } from "zod";

// Create structured output with zod
const { Workflow, smithers } = createSmithers({
  greeting: z.object({
    message: z.string(),
    perfect: z.boolean(),
  }),
});

// use the ai sdk or built in codex/claude cli agents
const greeter = agent({
  model: anthropic("claude-sonnet-4-20250514"),
  system: "You are a greeting expert.",
});

// export a react component specifying your agent's "Plan" as simple JSX that can evolve over time
// Everytime a task finishes the react component will rerender allowing plans to evolve over time
export default smithers((ctx) => (
  <Workflow name="hello-world">
    <Ralph
      until={ctx.latest("greeting", "greet")?.perfect}
      maxIterations={3}
    >
      <Task
        id="greet"
        output="greeting"
        agent={greeter}
        retries={1}
      >
        {`Write the perfect hello world greeting. ${
          ctx.latest("greeting", "greet")?.message
            ? `Your last attempt was: "${
                ctx.latest("greeting", "greet").message
              }" — make it better.`
            : ""
        }`}
      </Task>
    </Ralph>
  </Workflow>
));
```

------

# What You Get with Smithers

Smithers is a **React-based workflow runtime for AI tasks**.

You define a workflow graph with JSX, store inputs and outputs in SQLite, and execute deterministically with durable state.

In practice, this gives you:

- Predictable execution and resumable runs
- LLMs are great at writing React thus great at writing smithers
- Durable outputs in SQLite (including chat histories)
- Great observability
- Incredible code reuse

------

# Declarative Orchestration with React

Here is the top-level entrypoint file for a real automated coding pipeline I am running as I write this article. How it works:

1. Discovers tasks
2. Implements them
3. Reviews its own work
4. Persists everything durably

```tsx
// workflow.tsx
import { Sequence, Branch } from "smithers-orchestrator";
import { Discover, TicketPipeline } from "./components";
import { Ticket } from "./components/Discover.schema";
import { Workflow, smithers, tables } from "./smithers";

export default smithers((ctx) => {
  const discoverOutput = ctx.latest(tables.discover, "discover-codex");

  const unfinishedTickets = ctx
    .latestArray(discoverOutput?.tickets, Ticket)
    .filter((t) => !ctx.latest(tables.report, `${t.id}:report`)) as Ticket[];

  return (
    <Workflow name="smithers-v2-workflow">
      <Sequence>
        <Branch if={unfinishedTickets.length === 0} then={<Discover />} />
        {unfinishedTickets.map((ticket) => (
          <TicketPipeline key={ticket.id} ticket={ticket} />
        ))}
      </Sequence>
    </Workflow>
  );
});
```

Each render returns a plan represented as a DAG of `<Task />` nodes.

When a task finishes:

1. Smithers persists the output to SQLite.
2. The workflow re-renders.
3. You can keep, modify, or completely change the plan.

You encapsulate behavior into reusable components like `<Discover />` and `<TicketPipeline />`.

------

## The Five Primitives

Smithers has five core building blocks:

- `<Sequence>` — run children sequentially.
- `<Parallel>` — run children concurrently.
- `<Branch>` — conditional execution.
- `<Ralph>` — loop until condition or max iterations.
- `<Task>` — leaf node that executes an agent or code and validates output.

------

# Components as Pipeline Stages

## Discover Stage

The `Discover` component generates tickets based on repository state and a PRD prompt.

```tsx
// components/Discover.tsx
import { Task } from "smithers-orchestrator";
import { codex } from "../agents";
import DiscoverPrompt from "./Discover.mdx";
import { Ticket } from "./Discover.schema";
import { useCtx, tables } from "../smithers";

export function Discover() {
  const ctx = useCtx();

  const discoverOutput = ctx.latest(tables.discover, "discover-codex");
  const allTickets = ctx.latestArray(discoverOutput?.tickets, Ticket);

  const completedIds = allTickets
    .filter((t) => !!ctx.latest(tables.report, `${t.id}:report`))
    .map((t) => t.id);

  const previousRun =
    completedIds.length > 0
      ? {
          summary: `Tickets completed: ${completedIds.join(", ")}`,
          ticketsCompleted: completedIds,
        }
      : null;

  return (
    <Task id="discover-codex" output={tables.discover} agent={codex}>
      <DiscoverPrompt previousRun={previousRun} />
    </Task>
  );
}
```

### Ticket Schema

```ts
import { z } from "zod";

export const Ticket = z.object({
  id: z.string(),
  title: z.string(),
  description: z.string(),
  scope: z.enum(["zig", "swift", "web", "e2e", "docs", "build"]),
  layers: z.array(z.string()),
  acceptanceCriteria: z.array(z.string()),
  testPlan: z.string(),
  estimatedComplexity: z.enum(["trivial", "small", "medium", "large"]),
  dependencies: z.array(z.string()).nullable(),
});
```

Smithers guarantees schema-valid JSON before the workflow proceeds.

------

# Ticket Pipeline

Each ticket runs through:

1. Research
2. Plan
3. Implement
4. Validate
5. Review
6. Report

```tsx
// components/TicketPipeline.tsx
import { Sequence } from "smithers-orchestrator";
import { Research } from "./Research";
import { Plan } from "./Plan";
import { ValidationLoop } from "./ValidationLoop";
import { Report } from "./Report";

export function TicketPipeline({ ticket }) {
  return (
    <Sequence key={ticket.id}>
      <Research ticket={ticket} />
      <Plan ticket={ticket} />
      <ValidationLoop ticket={ticket} />
      <Report ticket={ticket} />
    </Sequence>
  );
}
```

------

# Validation Loop

```tsx
import { Ralph, Sequence } from "smithers-orchestrator";

export function ValidationLoop({ ticket }) {
  return (
    <Ralph
      id={`${ticket.id}:impl-review-loop`}
      until={/* both reviewers approve */}
      maxIterations={5}
      onMaxReached="return-last"
    >
      <Sequence>
        <Implement ticket={ticket} />
        <Validate ticket={ticket} />
        <Review ticket={ticket} />
        <ReviewFix ticket={ticket} />
      </Sequence>
    </Ralph>
  );
}
```

`<Validate />` runs real CI.
`<Review />` runs multiple model reviewers in parallel.
The loop continues until both approve or max iterations are reached.

------

# Structured Output

### Validation Schema

```ts
export const ValidateOutput = z.object({
  allPassed: z.boolean(),
  failingSummary: z.string().nullable(),
  fullOutput: z.string(),
});
```

### Register Schemas

```ts
export const { Workflow, useCtx, smithers, tables } =
  createSmithers(
    {
      discover: DiscoverOutput,
      research: ResearchOutput,
      plan: PlanOutput,
      implement: ImplementOutput,
      validate: ValidateOutput,
      review: ReviewOutput,
      reviewFix: ReviewFixOutput,
      report: ReportOutput,
    },
    { dbPath: "./smithers-v2.db" }
  );
```

Every `<Task />` writes structured, validated output to SQLite.

------

# Reusability

This entire pipeline will become a reusable:

```tsx
<KanbanRalph prd={...} />
```

Drop in a PRD and some other system prompts.
Run for hours.
Stop. Restart. Self-correct.

This is what reusable agent workflows should feel like.

------

# Monitoring and Debugging

- All outputs stored in SQLite.
- All plan frames persisted.
- Deterministic node identities.
- Resume without duplication.
- Time travel possible (especially with JJ).

No “did it run twice?” uncertainty.

State is the source of truth.

------

# Self-Healing Systems

Because workflows are durable and declarative:

- You can fail over models at runtime.
- You can modify harness behavior mid-run.
- You can restart without losing state.

Long-running Ralph loops can self-heal.

The workflow itself becomes evolvable software.

------

# Takeaways

### Declarative over Imperative

JSX replaces nested state machines.
Adding a stage = adding a line.

### Colocation over Separation

Logic, prompt, and schema live together.

### Context over Props

Components read from durable workflow state.

### Schemas over Manual Types

Zod provides runtime validation + TypeScript types.

### Derive over Store

Compute from state. Avoid redundant persistence.

------

The entire system — parallel reviews, looping validation, durable state, conditional discovery — fits in a few hundred lines of JSX.

The runtime handles the rest.

------

# Explore Smithers

- Docs: [https://smithers.sh](https://smithers.sh/)
- Repo: https://github.com/evmts/smithers
- Example workflow: https://github.com/evmts/agent

Plan mode as code. Durable. Deterministic. Reusable.
