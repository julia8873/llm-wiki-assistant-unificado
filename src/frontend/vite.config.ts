import { defineConfig, loadEnv } from 'vite'
import react from '@vitejs/plugin-react'

// https://vitejs.dev/config/
export default defineConfig(({ mode }) => {
  // Carga las variables de entorno, incluyendo las que no tienen prefijo VITE_
  const env = loadEnv(mode, process.cwd(), '')

  return {
    plugins: [react()],
    server: {
      port: parseInt(env.PORT),
      strictPort: true,
      host: true,
      // Útil cuando se usa un proxy inverso (ej: Ngrok, Traefik, Nginx)
      ...(env.VITE_HMR_PORT && { hmr: { clientPort: parseInt(env.VITE_HMR_PORT) } }),
      proxy: {
        '/api': {
          // La URL se inyecta desde docker-compose.yml (o .env)
          target: env.VITE_API_TARGET_URL,
          changeOrigin: true,
          rewrite: (path) => path.replace(/^\/api/, '')
        }
      }
    }
  }
})
