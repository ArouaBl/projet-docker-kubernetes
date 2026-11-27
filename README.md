# TP — Conteneurisation et Orchestration (Docker Compose puis Kubernetes/Minikube)

Application micro-services : **frontend** (nginx), **API** (Node.js/Express) et **Redis** (persistant).

```
Navigateur --> frontend (nginx) --/api/--> api (N réplicas) --> redis (volume)
```

## Sommaire
1. [Prérequis](#prérequis)
2. [Démarrage rapide](#démarrage-rapide)
3. [Démo : commandes, utilité et résultats](#démo--commandes-utilité-et-résultats)
   - [Qualité des Dockerfile](#1-qualité-des-dockerfile)
   - [Composition locale (docker-compose.yml)](#2-composition-locale--docker-composeyml)
   - [Déploiement sur Minikube](#3-déploiement-sur-minikube)
   - [Test de scalabilité](#4-test-de-scalabilité)
   - [Test de résilience](#5-test-de-résilience)
   - [Volumes, données persistantes et réseau](#6-volumes-données-persistantes-et-réseau)
   - [Reproductibilité](#7-reproductibilité)
4. [Contenu du dépôt](#contenu-du-dépôt)

## Prérequis
Docker Desktop, Minikube, kubectl. Sous Windows, utiliser **Git Bash** pour les scripts `.sh`.

## Démarrage rapide

### Partie 1 : Docker Compose
```bash
docker compose up -d --build
docker compose ps
```
Application : http://localhost:8081 — arrêt : `docker compose down` (les données restent dans le volume `redis-data`).

### Partie 2 : Kubernetes avec Minikube
Arrêter d'abord Compose (`docker compose down`), puis :
```bash
bash deploy-minikube.sh
kubectl -n tp-conteneurs get all,pvc
```
Accès à l'application (laisser ce terminal ouvert) :
```bash
kubectl -n tp-conteneurs port-forward svc/frontend 8081:8080
```
Puis ouvrir http://localhost:8081. Si le port 8081 est occupé, utiliser par exemple `8082:8080`.

**Après un redémarrage du PC :** lancer Docker Desktop, puis `minikube start --driver=docker` et `kubectl get pods -n tp-conteneurs`. Si les pods sont en `ErrImageNeverPull` :
```bash
minikube image load tp/api:1.0
minikube image load tp/frontend:1.0
kubectl -n tp-conteneurs rollout restart deploy/api deploy/frontend
```
Si le cluster a disparu, relancer `bash deploy-minikube.sh`.

> Astuce : `kubectl config set-context --current --namespace=tp-conteneurs` évite d'écrire `-n tp-conteneurs` à chaque commande.

---

# Démo : commandes, utilité et résultats

## 1. Qualité des Dockerfile

| Commande | Utilité | Résultat attendu |
|---|---|---|
| `docker images \| grep tp/` | Affiche les images et leur taille | api 204 Mo (contenu 49,2 Mo), frontend 73,7 Mo (21 Mo) |
| `docker history tp/api:1.0` | Montre les couches de l'image et leur taille | Peu de couches, pas de cache npm : effet du multi-stage |
| `docker run --rm --entrypoint whoami tp/api:1.0` | Affiche l'utilisateur dans le conteneur | Réponse `node` : pas de root |
| `docker build -t tp/api:1.0 ./api` | Reconstruit l'image | Les couches déjà construites sont réutilisées (`CACHED`) |
| `cat api/Dockerfile` | Affiche le fichier | 2 étapes, alpine, `USER node`, `HEALTHCHECK`, `COPY package.json` avant le code |

## 2. Composition locale — docker-compose.yml

| Commande | Utilité | Résultat attendu |
|---|---|---|
| `docker compose up -d --build` | Construit et démarre tous les services | Redis puis api `Healthy`, puis frontend `Started` |
| `docker compose ps` | État des conteneurs | 3 services `Up`, api et redis `healthy` |
| `docker compose logs -f api` | Suit les journaux de l'API (Ctrl+C pour quitter) | Message « API sur :3000 » |
| `docker compose config` | Affiche le fichier Compose interprété | Permet de vérifier la syntaxe |
| `docker compose exec redis redis-cli lrange tasks 0 -1` | Lit les tâches directement dans Redis | Liste des tâches : les données sont dans Redis |
| `docker compose up -d --scale api=3` | Lance 3 conteneurs API | Possible car l'API n'expose aucun port sur l'hôte |
| `docker compose down` | Arrête et supprime conteneurs et réseaux | Le volume est conservé |
| `docker compose down -v` | Supprime aussi le volume | Attention : efface les données |

Application sur http://localhost:8081 (port 8080 évité à cause d'un conflit).

## 3. Déploiement sur Minikube

| Commande | Utilité | Résultat attendu |
|---|---|---|
| `minikube status` | État du cluster | host, kubelet, apiserver : `Running` |
| `kubectl get nodes` | Liste les nœuds | `minikube   Ready` |
| `kubectl get all,pvc -n tp-conteneurs` | Vue d'ensemble des ressources | Pods `Running`, 3 services, 3 deployments, HPA, PVC `Bound` |
| `kubectl get pods -n tp-conteneurs -o wide` | Pods avec IP et nœud | Chaque pod a sa propre IP |
| `kubectl describe pod NOM -n tp-conteneurs` | Détail d'un pod : événements, probes, limites | Utile pour diagnostiquer une erreur |
| `kubectl logs deploy/api -n tp-conteneurs` | Journaux de l'API | Démarrage et erreurs éventuelles |
| `kubectl get svc -n tp-conteneurs` | Liste les Services | api et redis en ClusterIP, frontend en NodePort 30080 |
| `kubectl get endpoints api -n tp-conteneurs` | IP des pods derrière le Service api | Plusieurs IP : le Service répartit entre elles |
| `kubectl apply -f k8s/` | Applique les manifestes | `created`, `configured` ou `unchanged` |
| `kubectl rollout status deploy/api -n tp-conteneurs` | Attend la fin du déploiement | `successfully rolled out` |
| `kubectl rollout undo deploy/api -n tp-conteneurs` | Retour à la version précédente | Illustre le rolling update |
| `kubectl port-forward svc/frontend 8081:8080 -n tp-conteneurs` | Ouvre l'accès local à l'application | http://localhost:8081 |

## 4. Test de scalabilité

| Commande | Utilité | Résultat attendu |
|---|---|---|
| `kubectl -n tp-conteneurs scale deploy/api --replicas=5` | Passe l'API à 5 réplicas | `deployment.apps/api scaled` |
| `kubectl -n tp-conteneurs get pods -l app=api` | Liste les pods de l'API | 5 pods `Running` |
| `kubectl -n tp-conteneurs run test --rm -it --image=busybox --restart=Never -- sh` | Ouvre un pod temporaire dans le cluster | Invite `/ #` |
| `for i in $(seq 10); do wget -qO- http://api:3000/api/info; echo; done` | Envoie 10 requêtes au Service (dans le pod temporaire) | Plusieurs valeurs différentes de `served_by` |
| `kubectl -n tp-conteneurs scale deploy/api --replicas=2` | Retour à 2 réplicas | Les pods en trop passent en `Terminating` |
| `kubectl get hpa -n tp-conteneurs` | État de l'autoscaler | min 2, max 6, cible 60 % CPU |

- Kubernetes crée les pods manquants et le Service `api` répartit les requêtes (visible avec `served_by`).
- `total_hits` est partagé car il est stocké dans Redis.
- **Attention au HPA :** il impose `minReplicas: 2` et peut ramener le nombre de pods vers la valeur calculée à partir de la charge CPU après un délai de stabilisation. On ne peut pas descendre durablement sous 2 réplicas tant que le HPA existe.
- Le script `bash test-scalabilite.sh` enchaîne scalabilité, résilience et persistance.

## 5. Test de résilience

| Commande | Utilité | Résultat attendu |
|---|---|---|
| `kubectl -n tp-conteneurs delete pod -l app=api` | Supprime les pods de l'API | Pods `deleted` |
| `kubectl -n tp-conteneurs get pods -l app=api` | Vérifie la recréation | Nouveaux pods créés automatiquement |

Le Deployment recrée les pods supprimés pour retrouver le nombre voulu. Au début ils sont `0/1` : la *readinessProbe* les garde hors du Service tant qu'ils ne sont pas prêts.

## 6. Volumes, données persistantes et réseau

| Commande | Utilité | Résultat attendu |
|---|---|---|
| `kubectl get pvc,pv -n tp-conteneurs` | Volume demandé et volume lié | `redis-pvc` `Bound`, 1Gi, RWO |
| `kubectl exec deploy/redis -n tp-conteneurs -- redis-cli lrange tasks 0 -1` | Lit les tâches dans Redis | Liste des tâches stockées |
| `kubectl rollout restart deploy/redis -n tp-conteneurs` | Remplace le pod Redis | Nouveau pod, même volume |
| `kubectl rollout status deploy/redis -n tp-conteneurs` | Attend la fin du redémarrage | `successfully rolled out` |
| `docker volume ls` | Volumes Docker (Compose) | `tp-conteneurs_redis-data` |
| `docker network ls` | Réseaux Docker | `tp-conteneurs_front-net` et `tp-conteneurs_back-net` |
| `docker network inspect tp-conteneurs_back-net` | Détail d'un réseau | `"Internal": true`, avec api et redis seulement |
| `docker compose exec frontend wget -qO- http://redis:6379` | Teste l'isolation de Redis | Échec (nom introuvable) : le frontend n'est pas sur `back-net` |

**Scénario de persistance :** ajouter une tâche dans l'interface → `kubectl -n tp-conteneurs rollout restart deploy/redis` → `rollout status` → recharger la page : la tâche est toujours là. Redis écrit dans `/data`, monté sur le PVC, qui survit au pod.

**Réseau Kubernetes :** `api` et `redis` sont en ClusterIP (internes), seul `frontend` est exposé. Les pods se joignent par le nom du Service (DNS interne), par exemple `http://api:3000`.

## 7. Reproductibilité

| Commande | Utilité | Résultat attendu |
|---|---|---|
| `bash deploy-minikube.sh` | Déploiement Kubernetes complet | `successfully rolled out` pour les 3 déploiements |
| `bash test-scalabilite.sh` | Tests automatiques (scale, résilience, persistance) | Sorties de chaque étape |
| `kubectl delete -f k8s/` | Nettoyer les ressources | Ressources `deleted` |
| `minikube stop` | Arrêter le cluster (garde l'état) | Cluster arrêté |
| `minikube delete` | Tout supprimer | Cluster supprimé |

---

## Contenu du dépôt
- `api/` et `frontend/` : code et Dockerfile (multi-stage pour l'API, utilisateur non-root)
- `docker-compose.yml` : 3 services, 2 réseaux (`back-net` interne), 1 volume
- `k8s/` : namespace, Deployments, Services, ConfigMap, PVC, HPA
- `deploy-minikube.sh`, `test-scalabilite.sh` : scripts de déploiement et de test
