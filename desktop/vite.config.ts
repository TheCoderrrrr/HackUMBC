import { defineConfig, loadEnv } from "vite";
import react from "@vitejs/plugin-react";

// The browser only talks to this dev server; `/api/*` is forwarded to the FastAPI backend,
// so the backend needs no CORS setup. Point BACKEND_URL at a tunnel to use a remote backend.
export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), "");
  const target = env.BACKEND_URL || "http://127.0.0.1:8000";
  return {
    plugins: [react()],
    define: { __BACKEND_TARGET__: JSON.stringify(target) },
    server: {
      port: 5173,
      fs: { allow: [".."] },
      proxy: {
        "/api": {
          target,
          changeOrigin: true,
          rewrite: (path) => path.replace(/^\/api/, ""),
          headers: {
            "ngrok-skip-browser-warning": "1",
            ...(env.DEMO_KEY ? { "X-Demo-Key": env.DEMO_KEY } : {}),
          },
        },
      },
    },
    preview: {
      proxy: {
        "/api": {
          target,
          changeOrigin: true,
          rewrite: (path) => path.replace(/^\/api/, ""),
          headers: {
            "ngrok-skip-browser-warning": "1",
            ...(env.DEMO_KEY ? { "X-Demo-Key": env.DEMO_KEY } : {}),
          },
        },
      },
    },
  };
});
