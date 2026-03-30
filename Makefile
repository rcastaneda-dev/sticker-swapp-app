dev:
	set -a && source .env && set +a && cd go_service && go run cmd/server/main.go

test:
	cd go_service && go test ./...

migrate:
	cd supabase && supabase db reset

build:
	cd go_service && CGO_ENABLED=0 go build -ldflags="-s -w" -trimpath -o ../bin/server ./cmd/server

docker-build:
	docker build -t sticker-swap-api:local -f go_service/Dockerfile go_service

docker-run:
	docker run --rm -p 8080:8080 --env-file .env sticker-swap-api:local