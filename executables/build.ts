import { readdir, mkdir } from 'fs/promises';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';
import { existsSync } from 'fs';

const __dirname = dirname(fileURLToPath(import.meta.url));
const executablesDir = __dirname;
const outputDir = join(executablesDir, '..', 'bin');

async function buildExecutables() {
  // Ensure output directory exists
  if (!existsSync(outputDir)) {
    await mkdir(outputDir, { recursive: true });
  }

  const entries = await readdir(executablesDir, { withFileTypes: true });
  const executablePackages = entries
    .filter(entry => entry.isDirectory() && entry.name.startsWith('plue-'))
    .map(entry => entry.name);

  console.log(`Found executables: ${executablePackages.join(', ')}`);

  for (const pkg of executablePackages) {
    const entryPoint = join(executablesDir, pkg, 'src', 'index.ts');
    
    // Skip if entry point doesn't exist
    if (!existsSync(entryPoint)) {
      console.log(`Skipping ${pkg} - no entry point found`);
      continue;
    }

    console.log(`Building ${pkg}...`);
    
    const result = await Bun.build({
      entrypoints: [entryPoint],
      outdir: outputDir,
      target: 'bun',
      naming: pkg,
      minify: true,
      sourcemap: 'none',
    });

    if (!result.success) {
      console.error(`Build failed for ${pkg}:`);
      for (const log of result.logs) {
        console.error(log);
      }
      process.exit(1);
    }

    // Now compile to standalone executable
    console.log(`Compiling ${pkg} to standalone executable...`);
    const { stdout, stderr, exitCode } = Bun.spawnSync([
      'bun', 
      'build', 
      '--compile',
      entryPoint,
      '--outfile',
      join(outputDir, pkg),
    ]);

    if (exitCode !== 0) {
      console.error(`Compilation failed for ${pkg}:`);
      console.error(stderr.toString());
      process.exit(1);
    }
  }

  console.log('All executables built successfully!');
}

buildExecutables().catch(err => {
  console.error('Build failed:', err);
  process.exit(1);
});