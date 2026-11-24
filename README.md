# TP — Conteneurisation et Orchestration (Docker Compose puis Kubernetes/Minikube)

Application micro-services : **frontend** (nginx), **API** (Node.js/Express) et **Redis** (persistant).

    Navigateur --> frontend (nginx) --/api/--> api (N réplicas) --> redis (volume)

## Prérequis
Docker Desktop, Minikube, kubectl. Sous Windows, utiliser Git Bash.

## Partie 1 : Docker Compose
```bash
docker compose up -d --build
docker compose ps
```
Application : http://localhost:8081

Arrêt : `docker compose down` (les données sont gardées dans le volume `redis-data`).

## Partie 2 : Kubernetes avec Minikube
Arrêter d'abord Compose (`docker compose down`), puis :
```bash
bash deploy-minikube.sh
kubectl -n tp-conteneurs get all,pvc
```
Accès à l'application (laisser ce terminal ouvert) :
```bash
kubectl -n tp-conteneurs port-forward svc/frontend 8081:8080
```
Puis ouvrir http://localhost:8081

### Test de scalabilité
```bash
kubectl -n tp-conteneurs scale deploy/api --replicas=5
kubectl -n tp-conteneurs get pods -l app=api
kubectl -n tp-conteneurs run test --rm -it --image=busybox --restart=Never -- sh
# dans le pod :
for i in $(seq 10); do wget -qO- http://api:3000/api/info; echo; done
```
Le champ `served_by` change : le Service répartit les requêtes entre les pods.
Retour à 2 réplicas : `kubectl -n tp-conteneurs scale deploy/api --replicas=2`.

Le script `bash test-scalabilite.sh` enchaîne scalabilité, résilience et persistance.

### Test de persistance
```bash
kubectl -n tp-conteneurs rollout restart deploy/redis
kubectl -n tp-conteneurs rollout status deploy/redis
```
Les tâches sont conservées grâce au PersistentVolumeClaim `redis-pvc`.

## Contenu du dépôt
- `api/` et `frontend/` : code et Dockerfile (multi-stage pour l'API, utilisateur non-root)
- `docker-compose.yml` : 3 services, 2 réseaux (`back-net` interne), 1 volume
- `k8s/` : namespace, Deployments, Services, ConfigMap, PVC, HPA
- `deploy-minikube.sh`, `test-scalabilite.sh` : scripts de déploiement et de test

## Nettoyage
```bash
kubectl delete -f k8s/
minikube stop
```
