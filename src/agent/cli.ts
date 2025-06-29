import { runSync, logError } from "effect/Effect";
import * as Command from "@effect/cli/Command";

const ac = new AbortController();

process.on("unhandledRejection", (e) => {
  runSync(logError("unhandledRejection", e instanceof Error ? e.message : e));
});

process.on("uncaughtException", (e) => {
  runSync(logError("uncaughtException", e instanceof Error ? e.message : e));
});

const command = Command.make("hello");

export const run = Command.run(command, {
  name: "Hello World",
  version: "0.0.0",
});
