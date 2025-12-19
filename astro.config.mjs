import { defineConfig } from 'astro/config';
import node from '@astrojs/node';

export default defineConfig({
  srcDir: './ui',
  output: 'server',
  adapter: node({
    mode: 'standalone'
  }),
  server: {
    port: 5173
  }
});
