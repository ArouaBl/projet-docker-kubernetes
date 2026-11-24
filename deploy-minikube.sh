#!/usr/bin/env bash
set -euo pipefail
minikube start --driver=docker
minikube addons enable metrics-server
# Les images ont été construites par "docker compose build/up"
docker build -t tp/api:1.0 ./api
docker build -t tp/frontend:1.0 ./frontend
minikube image load tp/api:1.0
minikube image load tp/frontend:1.0
kubectl apply -f k8s/
kubectl -n tp-conteneurs rollout status deploy/redis
kubectl -n tp-conteneurs rollout status deploy/api
kubectl -n tp-conteneurs rollout status deploy/frontend
kubectl -n tp-conteneurs get all,pvc
echo
echo "Pour accéder à l'app : kubectl -n tp-conteneurs port-forward svc/frontend 8081:8080"
echo "puis ouvrir http://localhost:8081"
