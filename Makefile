
# Image URL to use all building/pushing image targets
TAG ?= latest
IMG ?= kudobuilder/controller:${TAG}
EXECUTABLE := manager
CLI := kubectl-kudo

all: test manager

deps:
	go install github.com/kudobuilder/kudo/vendor/github.com/golang/dep/cmd/dep
	dep check -skip-vendor
	go install github.com/kudobuilder/kudo/vendor/golang.org/x/tools/cmd/goimports
	go install github.com/kudobuilder/kudo/vendor/golang.org/x/lint/golint
	go get -u honnef.co/go/tools/cmd/staticcheck

# Run tests
test: generate deps fmt vet lint imports manifests
	go test ./pkg/... ./cmd/... -coverprofile cover.out

# Clean test reports
test-clean:
	rm -f cover.out

check-formatting: generate deps vet lint staticcheck
	./test/formatting.sh

prebuild: generate fmt vet

# Build manager binary
manager: prebuild
	# developer convince for platform they are running
	go build -o bin/$(EXECUTABLE) github.com/kudobuilder/kudo/cmd/manager

	# platforms for distribution
	GOARCH=amd64 GOOS=darwin go build -o bin/darwin/amd64/$(EXECUTABLE) github.com/kudobuilder/kudo/cmd/manager
	GOARCH=amd64 GOOS=linux go build -o bin/linux/amd64/$(EXECUTABLE) github.com/kudobuilder/kudo/cmd/manager
	GOARCH=amd64 GOOS=windows go build -o bin/windows/amd64/$(EXECUTABLE) github.com/kudobuilder/kudo/cmd/manager

# Clean manager build
manager-clean:
	rm -f bin/manager
	rm -rf bin/darwin/amd64/$(EXECUTABLE)
	rm -rf bin/linux/amd64/$(EXECUTABLE)
	rm -rf bin/windows/amd64/$(EXECUTABLE)

# Run against the configured Kubernetes cluster in ~/.kube/config
run: generate fmt vet
	go run ./cmd/manager/main.go

# Install CRDs into a cluster
install: manifests
	kubectl apply -f config/crds

# Deploy controller in the configured Kubernetes cluster in ~/.kube/config
deploy: manifests
	kubectl apply -f config/crds
	kustomize build config/default | kubectl apply -f -

deploy-clean:
	kubectl delete -f config/crds
	# kustomize build config/default | kubectl delete -f -

# Generate manifests e.g. CRD, RBAC etc.
manifests:
	# controller-gen/main.go all == [rbac, crd]
	go run vendor/sigs.k8s.io/controller-tools/cmd/controller-gen/main.go rbac --output-dir=config/default/rbac
	go run vendor/sigs.k8s.io/controller-tools/cmd/controller-gen/main.go crd

# Run go fmt against code
fmt:
	go fmt ./pkg/... ./cmd/...

# Run go vet against code
vet:
	go vet ./pkg/... ./cmd/...

# Run go lint against code
lint:
	golint ./pkg/... ./cmd/...

# Runs static check
staticcheck:
	staticcheck ./...

# Run go imports against code
imports:
	goimports ./pkg/ ./cmd/

# Generate code
generate:
	go generate ./pkg/... ./cmd/...

# Build CLI
cli: prebuild
	# developer convince for platform they are running
	go build -o bin/${CLI} cmd/kubectl-kudo/main.go

	# platforms for distribution
	GOARCH=amd64 GOOS=darwin go build -o bin/darwin/amd64/${CLI} cmd/kubectl-kudo/main.go
	GOARCH=amd64 GOOS=linux go build -o bin/linux/amd64/${CLI} cmd/kubectl-kudo/main.go
	GOARCH=amd64 GOOS=windows go build -o bin/windows/${CLI} cmd/kubectl-kudo/main.go

# Clean CLI build
cli-clean:
	rm -f bin/${CLI}
	rm -rf bin/darwin/amd64/${CLI}
	rm -rf bin/linux/amd64/${CLI}
	rm -rf bin/windows/${CLI}

# Clean all
clean:  cli-clean test-clean manager-clean deploy-clean
	rm -rf bin/darwin
	rm -rf bin/linux
	rm -rf bin/windows

# Build the docker image
docker-build: generate fmt vet manifests
	docker build . -t ${IMG}
	@echo "updating kustomize image patch file for manager resource"
	sed -i'' -e 's@image: .*@image: '"${IMG}"'@' ./config/default/manager_image_patch.yaml

# Push the docker image
docker-push:
	docker push ${IMG}
