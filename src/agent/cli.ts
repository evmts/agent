import * as Effect from "effect/Effect";
import * as Command from "@effect/cli/Command";
import * as Console from "effect/Console";
import * as Option from "effect/Option";
import { printLogs } from "./options";
import {
  tuiCommand,
  runCommand,
  generateCommand,
  scrapCommand,
  authCommand,
  upgradeCommand,
  serveCommand,
  modelsCommand,
} from "./commands";

const mainCommand = Command.make("plue", { printLogs }, ({ printLogs }) =>
  Effect.gen(function*() {
    yield* printLogs.pipe(
      Option.match({
        onNone: () => Effect.void,
        onSome: () => Console.log("Logging enabled"),
      }),
    );
    yield* Console.log("Plue CLI - Multi-Agent Coding Assistant");
    yield* Console.log("Use 'plue --help' for available commands");
  }),
).pipe(
  Command.withDescription("Plue multi-agent coding assistant CLI"),
  Command.withSubcommands([
    tuiCommand,
    runCommand,
    generateCommand,
    scrapCommand,
    authCommand,
    upgradeCommand,
    serveCommand,
    modelsCommand,
  ]),
);

const cli = Command.run(mainCommand, {
  name: "Plue CLI",
  version: "0.1.0",
});

export default cli;
