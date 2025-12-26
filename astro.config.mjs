import { defineConfig } from 'astro/config';
import node from '@astrojs/node';
import tailwind from '@astrojs/tailwind';
import AstroPWA from '@vite-pwa/astro';
import mkcert from 'vite-plugin-mkcert';

// Edge worker URL for auth routes (dev mode)
const EDGE_URL = process.env.EDGE_URL || 'http://localhost:8787';

export default defineConfig({
  srcDir: './ui',
  publicDir: './ui/public',
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
    },
    server: {
      proxy: {
        // Proxy auth routes to edge worker in dev mode
        '/api/auth': {
          target: EDGE_URL,
          changeOrigin: true,
          secure: false,
        },
      },
    },
  }
});