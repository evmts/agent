import * as Options from "@effect/cli/Options";

export const printLogs = Options.boolean("print-logs").pipe(
  Options.withDescription("Print logs to stderr"),
  Options.optional,
);