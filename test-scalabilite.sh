#!/usr/bin/env bash
NS=tp-conteneurs
kubectl -n $NS port-forward svc/frontend 8081:8080 >/dev/null 2>&1 &
PF=$!
trap "kill $PF 2>/dev/null" EXIT
sleep 3
URL=http://localhost:8081

echo "=== Scale API : 2 -> 5 réplicas ==="
kubectl -n $NS scale deploy/api --replicas=5
kubectl -n $NS rollout status deploy/api
kubectl -n $NS get pods -l app=api -o wide

echo "=== 10 requêtes (observer les différents served_by) ==="
for i in $(seq 10); do curl -s $URL/api/info; echo; done
echo "(port-forward cible un seul pod ; voir la note du README pour la répartition)"

echo "=== Scale API : 5 -> 1 ==="
kubectl -n $NS scale deploy/api --replicas=1
kubectl -n $NS get pods -l app=api

echo "=== Résilience : suppression d'un pod API ==="
kubectl -n $NS delete pod -l app=api --wait=false
sleep 8
kubectl -n $NS get pods -l app=api

echo "=== Persistance : redémarrage de Redis ==="
curl -s -X POST -H 'Content-Type: application/json' -d '{"title":"test-persistance"}' $URL/api/tasks; echo
kubectl -n $NS rollout restart deploy/redis
kubectl -n $NS rollout status deploy/redis
sleep 5
curl -s $URL/api/tasks; echo
