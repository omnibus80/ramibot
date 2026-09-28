import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'

const allowedHosts = (process.env.RAMIBOT_ALLOWED_HOSTS || '')
  .split(',')
  .map((host) => host.trim())
  .filter(Boolean)
  .concat(['.ngrok-free.dev', '.ngrok-free.app'])

const osirisTarget = process.env.OSIRIS_TARGET || `http://127.0.0.1:${process.env.OSIRIS_PORT || 3000}`
const backendTarget = `http://127.0.0.1:${process.env.RAMIBOT_BACKEND_PORT || 8001}`
const isOsirisRequest = (request) => (request.headers.referer || '').includes('/osiris')

export default defineConfig({
  plugins: [react(), tailwindcss()],
  server: {
    host: '0.0.0.0',
    allowedHosts,
    proxy: {
      '/api': {
        target: backendTarget,
        changeOrigin: true,
        router: (request) => isOsirisRequest(request) ? osirisTarget : undefined,
        configure: (proxy) => {
          proxy.on('proxyReq', (proxyRequest, request) => {
            if (isOsirisRequest(request)) proxyRequest.path = `/osiris${proxyRequest.path}`
          })
        },
      },
      '/osiris': {
        target: osirisTarget,
        changeOrigin: true,
        ws: true,
      },
      '^/(?!api(?:/|$)|osiris(?:/|$)|@vite|@id|@react-refresh|src/|node_modules/|assets/).*': {
        target: osirisTarget,
        changeOrigin: true,
        ws: true,
        bypass: (request) => isOsirisRequest(request) ? undefined : request.url,
      },
    },
  },
})
