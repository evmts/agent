#!/usr/bin/env node

import * as NodeContext from "@effect/platform-node/NodeContext";
import * as NodeRuntime from "@effect/platform-node/NodeRuntime";
import * as Effect from "effect/Effect";
import cli from "./cli.js";

process.on("unhandledRejection", (e) => {
  console.error("Unhandled rejection:", e);
  process.exit(1);
});

process.on("uncaughtException", (e) => {
  console.error("Uncaught exception:", e);
  process.exit(1);
});

cli(process.argv).pipe(
  Effect.provide(NodeContext.layer),
  NodeRuntime.runMain({ disableErrorReporting: true }),
);
