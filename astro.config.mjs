import { defineConfig } from 'astro/config';
import node from '@astrojs/node';
import tailwind from '@astrojs/tailwind';
import AstroPWA from '@vite-pwa/astro';
import mkcert from 'vite-plugin-mkcert';

export default defineConfig({
  srcDir: './ui',
  output: 'server',
  adapter: node({
    mode: 'standalone'
  }),
  integrations: [tailwind(), AstroPWA()],
  vite: {
    plugins: [mkcert()],
    define: {
      'process.env.NODE_ENV': JSON.stringify(process.env.NODE_ENV || 'development')
    },
    ssr: {
      // Externalize native modules so Vite doesn't try to bundle them
      noExternal: [],
      external: ['@plue/snapshot']
    },
    optimizeDeps: {
      exclude: ['@plue/snapshot']
    }
  }
});