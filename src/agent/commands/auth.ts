import * as Command from "@effect/cli/Command";
import * as Console from "effect/Console";

export const authCommand = Command.make("auth", {}, () =>
  Console.log("Auth command not yet implemented"),
).pipe(Command.withDescription("Authenticate user"));