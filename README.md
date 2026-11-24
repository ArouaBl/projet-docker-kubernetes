# TP — Conteneurisation & Orchestration (Docker Compose → Kubernetes/Minikube)

Application micro-services : **Frontend** (nginx) → **API** (Node.js/Express) → **Redis** (persistant).

```
Navigateur ──8080──► frontend (nginx) ──/api/──► api (x N réplicas) ──► redis (volume)
```

## 1. Prérequis
Docker ≥ 24, Docker Compose v2, Minikube, kubectl.

## 2. Partie 1 — Docker & Compose
```bash
docker compose up -d --build
docker compose ps                  # api, redis -> "healthy"
open http://localhost:8080
```
**Persistance** : `docker compose down && docker compose up -d` → les tâches sont conservées (volume `redis-data`).
`docker compose down -v` supprime les données.

**Choix techniques (Dockerfile)**
| Choix | Justification |
|---|---|
| Multi-stage sur l'API (`deps` → image finale) | Aucun outil de build/cache npm dans l'image finale |
| Images `alpine` | Taille réduite (≈ 150 Mo API, ≈ 50 Mo front) |
| `USER node` / nginx-unprivileged | Pas d'exécution en root |
| `.dockerignore`, `npm cache clean` | Contexte et couches allégés |
| `HEALTHCHECK` | Permet `depends_on: service_healthy` |
| `COPY package.json` avant le code | Cache de couches optimal |

**Réseau** : deux réseaux. `front-net` (frontend↔api) et `back-net` (`internal: true`, api↔redis). Redis n'est joignable ni de l'extérieur ni du frontend. La résolution DNS se fait par nom de service (`api`, `redis`).

Mesurer : `docker images | grep tp/`

## 3. Partie 2 — Kubernetes (Minikube)
```bash
./deploy-minikube.sh               # start, build dans Minikube, apply, URL finale
kubectl -n tp-conteneurs get all,pvc
```
| Fichier | Contenu |
|---|---|
| `00-namespace.yaml` | Namespace `tp-conteneurs` |
| `10-redis.yaml` | PVC 1 Gi + Deployment (strategy Recreate) + Service ClusterIP |
| `20-api.yaml` | ConfigMap, Deployment (2 réplicas, probes liveness/readiness, limits), Service, HPA |
| `30-frontend.yaml` | Deployment (2 réplicas) + Service NodePort 30080 |

Le même `nginx.conf` marche en Compose et en K8s car le Service s'appelle `api` dans les deux cas.

### Test de scalabilité
```bash
./test-scalabilite.sh
# ou manuellement :
kubectl -n tp-conteneurs scale deploy/api --replicas=5
for i in $(seq 10); do curl -s $(minikube service frontend -n tp-conteneurs --url)/api/info; echo; done
```
Le champ `served_by` change d'un appel à l'autre : le Service répartit la charge entre pods.
Test HPA : `kubectl -n tp-conteneurs get hpa -w` pendant une charge (`hey`, `ab`, ou boucle `curl`).

### Tests de résilience / persistance
- Supprimer un pod API → le Deployment en recrée un, sans coupure (2+ réplicas).
- `kubectl rollout restart deploy/redis` → les données persistent grâce au PVC.

## 4. Docker Compose vs Kubernetes
| | Compose | Kubernetes |
|---|---|---|
| Scalabilité | `--scale api=3` (manuel, 1 hôte) | `replicas`, HPA automatique |
| Auto-guérison | `restart:` basique | Probes + recréation de pods |
| Mises à jour | Arrêt/relance | Rolling update |
| Réseau | Réseaux bridge + DNS | Services, ClusterIP/NodePort/Ingress |
| Données | Volumes nommés | PV/PVC, StorageClass |
| Usage | Dev local | Production, multi-nœuds |

## 5. Local vs Cloud
Les manifestes sont portables vers EKS/GKE/AKS : seuls changent le registre d'images (supprimer `imagePullPolicy: Never`, pousser vers un registre), le Service frontend (`LoadBalancer` ou Ingress) et la StorageClass.

## 6. Limites & améliorations
Redis à instance unique (→ StatefulSet/Sentinel), pas de TLS/Ingress, pas de Secrets (Redis sans mot de passe), pas de CI/CD.

## 7. Questions probables en démo
1. Différence VM / conteneur ? (noyau partagé, namespaces + cgroups)
2. Pourquoi multi-stage ? 3. Pod vs Deployment vs Service ?
4. Que se passe-t-il si un pod meurt ? 5. Pourquoi `Recreate` pour Redis ?
6. Liveness vs readiness ? 7. Comment passer en cloud ?
