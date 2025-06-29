import * as Command from "@effect/cli/Command";
import * as Console from "effect/Console";

export const modelsCommand = Command.make("models", {}, () =>
  Console.log("Models command not yet implemented"),
).pipe(Command.withDescription("Manage models"));