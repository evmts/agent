import * as Command from "@effect/cli/Command";
import * as Console from "effect/Console";

export const scrapCommand = Command.make("scrap", {}, () =>
  Console.log("Scrap command not yet implemented"),
).pipe(Command.withDescription("Scrap command"));