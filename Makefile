dev:
	cd supabase && supabase start
	cd go_service && go run cmd/server/main.go

test:
	cd go_service && go test ./...

migrate:
	cd supabase && supabase db reset