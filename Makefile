dev:
	set -a && source .env && set +a && cd go_service && go run cmd/server/main.go

test:
	cd go_service && go test ./...

test-integration:
	set -a && source .env && set +a && \
	cd go_service && go test -tags=integration -race -count=1 -timeout=120s ./internal/trades/...

test-loadtest:
	set -a && source .env && set +a && \
	cd go_service && go test -tags=integration -count=1 -timeout=1800s -v -run TestLoadProximityQueries ./internal/matchmaking/...

test-ably-loadtest:
	set -a && source .env && set +a && \
	cd go_service && go test -tags=integration -count=1 -timeout=600s -v -run TestAblyWebSocketLoadTest ./internal/ably/...

test-e2e:
	cd flutter_app && flutter test integration_test/

test-e2e-ios:
	cd flutter_app && flutter test integration_test/ -d "iPhone 16 Pro"

test-e2e-android:
	cd flutter_app && flutter test integration_test/ -d emulator-5554

migrate:
	cd supabase && supabase db reset

build:
	cd go_service && CGO_ENABLED=0 go build -ldflags="-s -w" -trimpath -o ../bin/server ./cmd/server

docker-build:
	docker build -t sticker-swap-api:local -f go_service/Dockerfile go_service

docker-run:
	docker run --rm -p 8080:8080 --env-file .env sticker-swap-api:local