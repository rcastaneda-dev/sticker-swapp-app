dev:
	set -a && source .env && set +a && cd go_service && go run cmd/server/main.go

test:
	cd go_service && go test ./...

migrate:
	cd supabase && supabase db reset