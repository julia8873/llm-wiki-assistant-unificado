import { defineConfig, loadEnv } from 'vite'
import react from '@vitejs/plugin-react'

// https://vitejs.dev/config/
export default defineConfig(({ mode }) => {
  // Carga las variables de entorno, incluyendo las que no tienen prefijo VITE_
  const env = loadEnv(mode, process.cwd(), '')

  if (!env.PORT) {
    throw new Error('La variable de entorno PORT no está definida')
  }

  const apiBaseUrl = env.VITE_API_BASE_URL || '/api'

  return {
    plugins: [react()],
    base: env.VITE_BASE_PATH || '/',
    server: {
      port: parseInt(env.PORT),
      strictPort: true,
      host: true,
      allowedHosts: env.VITE_ALLOWED_HOSTS ? env.VITE_ALLOWED_HOSTS.split(',') : [],
      // Útil cuando se usa un proxy inverso (ej: Ngrok, Traefik, Nginx)
      ...(env.VITE_HMR_PORT && { hmr: { clientPort: parseInt(env.VITE_HMR_PORT) } }),
      proxy: {
        [apiBaseUrl]: {
          // La URL se inyecta desde docker-compose.yml (o .env)
          target: env.VITE_API_TARGET_URL,
          changeOrigin: true,
          rewrite: (path) => path.replace(new RegExp(`^${apiBaseUrl}`), '')
        }
      }
    }
  }
})
