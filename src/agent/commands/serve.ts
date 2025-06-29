import * as Command from "@effect/cli/Command";
import * as Console from "effect/Console";

export const serveCommand = Command.make("serve", {}, () =>
  Console.log("Serve command not yet implemented"),
).pipe(Command.withDescription("Start the server"));