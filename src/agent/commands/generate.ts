import * as Command from "@effect/cli/Command";
import * as Console from "effect/Console";

export const generateCommand = Command.make("generate", {}, () =>
  Console.log("Generate command not yet implemented"),
).pipe(Command.withDescription("Generate code"));