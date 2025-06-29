import * as Effect from "effect/Effect";
import * as Command from "@effect/cli/Command";
import * as Args from "@effect/cli/Args";
import * as Console from "effect/Console";

export const runCommand = Command.make(
  "run",
  { script: Args.text({ name: "script" }).pipe(Args.optional) },
  ({ script }) =>
    Effect.gen(function* () {
      const scriptName = script._tag === "Some" ? script.value : "default";
      yield* Console.log(`Run command with script: ${scriptName}`);
    }),
).pipe(Command.withDescription("Run a script"));