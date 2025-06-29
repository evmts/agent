import Effect from "effect/Effect";

const ac = new AbortController();

process.on("unhandledRejection", (e) => {
  Effect.logError("unhandledRejection", e instanceof Error ? e.message : e);
});

process.on("uncaughtException", (e) => {
  Effect.logError("uncaughtException", e instanceof Error ? e.message : e);
});
