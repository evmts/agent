import * as Command from "@effect/cli/Command";
import * as Console from "effect/Console";

export const tuiCommand = Command.make("tui", {}, () =>
  Console.log("TUI command not yet implemented"),
).pipe(Command.withDescription("Launch the terminal user interface"));