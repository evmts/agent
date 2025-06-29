import * as Command from "@effect/cli/Command";
import * as Console from "effect/Console";

export const upgradeCommand = Command.make("upgrade", {}, () =>
  Console.log("Upgrade command not yet implemented"),
).pipe(Command.withDescription("Upgrade the CLI"));