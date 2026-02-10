import { plugin, type BunPlugin } from "bun";
import mdx from "@mdx-js/esbuild";

plugin(mdx() as unknown as BunPlugin);
