.PHONY: setup start deploy open-grafana open-victorialogs status logs-fluentbit logs-app cleanup help

## setup: Full setup — start Minikube and deploy all components
setup: start deploy

## start: Start Minikube cluster
start:
	@echo ">>> Starting Minikube..."
	minikube start

## deploy: Deploy all Kubernetes manifests and Helm releases
deploy:
	@echo ">>> Applying namespace..."
	kubectl apply -f k8s/namespace.yaml

	@echo ">>> Deploying VictoriaLogs..."
	kubectl apply -f k8s/victorialogs/

	@echo ">>> Waiting for VictoriaLogs to be ready..."
	kubectl rollout status deployment/victorialogs --namespace logging --timeout=120s
	kubectl wait --namespace logging \
		--for=condition=ready pod \
		--selector=app=victorialogs \
		--timeout=120s

	@echo ">>> Adding Helm repos..."
	helm repo add fluent https://fluent.github.io/helm-charts
	helm repo add grafana https://grafana.github.io/helm-charts
	helm repo update

	@echo ">>> Installing Fluent Bit..."
	helm upgrade --install fluent-bit fluent/fluent-bit \
		--namespace logging \
		--values k8s/fluentbit/values.yaml

	@echo ">>> Installing Grafana..."
	helm upgrade --install grafana grafana/grafana \
		--namespace logging \
		--values k8s/grafana/values.yaml

	@echo ">>> Deploying sample app..."
	kubectl apply -f k8s/sample-app/

	@echo ""
	@echo "✅ All components deployed."
	@echo "   Run 'make open-grafana' to open Grafana in your browser."
	@echo "   Grafana credentials: admin / admin123"

## open-grafana: Open Grafana in the browser via minikube service
open-grafana:
	@echo ">>> Opening Grafana..."
	minikube service grafana --namespace logging

## open-victorialogs: Port-forward VictoriaLogs UI to localhost:9428
open-victorialogs:
	@echo ">>> Port-forwarding VictoriaLogs to localhost:9428..."
	kubectl port-forward svc/victorialogs 9428:9428 --namespace logging

## status: Show pod status across all namespaces
status:
	@echo ">>> Pod status (all namespaces):"
	kubectl get pods --all-namespaces

## logs-fluentbit: Tail Fluent Bit pod logs
logs-fluentbit:
	@echo ">>> Tailing Fluent Bit logs..."
	kubectl logs --namespace logging -l app.kubernetes.io/name=fluent-bit -f

## logs-app: Tail sample-app pod logs
logs-app:
	@echo ">>> Tailing sample-app logs..."
	kubectl logs --namespace default -l app=sample-app -f

## cleanup: Delete all resources and stop Minikube
cleanup:
	@echo ">>> Removing Helm releases..."
	helm uninstall fluent-bit --namespace logging || true
	helm uninstall grafana --namespace logging || true

	@echo ">>> Deleting Kubernetes resources..."
	kubectl delete -f k8s/sample-app/ || true
	kubectl delete -f k8s/victorialogs/ || true
	kubectl delete -f k8s/namespace.yaml || true

	@echo ">>> Stopping Minikube..."
	minikube stop

	@echo "✅ Cleanup complete."

## help: Print all available targets with descriptions
help:
	@echo "Available targets:"
	@grep -E '^## ' Makefile | sed 's/## /  make /'
