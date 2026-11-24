const express = require("express");
const { createClient } = require("redis");
const os = require("os");

const PORT = process.env.PORT || 3000;
const REDIS_URL = process.env.REDIS_URL || "redis://redis:6379";

const app = express();
app.use(express.json());

const redis = createClient({ url: REDIS_URL });
redis.on("error", (e) => console.error("Redis error:", e.message));

// Liveness : le process répond
app.get("/api/health", (_req, res) => res.json({ status: "ok" }));
// Readiness : Redis joignable
app.get("/api/ready", async (_req, res) => {
  try { await redis.ping(); res.json({ ready: true }); }
  catch { res.status(503).json({ ready: false }); }
});

// Montre quel pod/conteneur répond (preuve du load-balancing)
app.get("/api/info", async (_req, res) => {
  const hits = await redis.incr("hits");
  res.json({ served_by: os.hostname(), total_hits: hits });
});

app.get("/api/tasks", async (_req, res) => {
  const items = await redis.lRange("tasks", 0, -1);
  res.json(items.map((t) => JSON.parse(t)));
});
app.post("/api/tasks", async (req, res) => {
  if (!req.body.title) return res.status(400).json({ error: "title requis" });
  const task = { id: Date.now().toString(36), title: req.body.title };
  await redis.rPush("tasks", JSON.stringify(task));
  res.status(201).json(task);
});
app.delete("/api/tasks/:id", async (req, res) => {
  const items = await redis.lRange("tasks", 0, -1);
  const target = items.find((t) => JSON.parse(t).id === req.params.id);
  if (target) await redis.lRem("tasks", 1, target);
  res.status(204).end();
});

(async () => {
  await redis.connect();
  const server = app.listen(PORT, () => console.log(`API sur :${PORT}`));
  process.on("SIGTERM", async () => {   // arrêt propre (rolling update)
    server.close(); await redis.quit(); process.exit(0);
  });
})();
