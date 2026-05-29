# Local Release Smoke Report Auth (20260529-145436)

## Scope
- Repository: OpenEdAI
- Host: promaxgb10-6116
- Generated: 2026-05-29T14:54:40+02:00

## Checklist Results
- make ci-local-status: 0
- make test-ci-all: 0
- make smoke-gateway-auth: 0
- systemctl --user status openedai-gateway.service: 0

## make ci-local-status
```txt
make[1]: Entering directory '/home/sameer/Public/Shared/Work/Projects/OpenEdAI'
bash scripts/ci/check_local_tools.sh
OpenEdAI Local CI Tooling Status

[ok] git: /usr/bin/git
[ok] make: /usr/bin/make
[ok] go: /snap/bin/go
[missing] shellcheck

shellcheck is missing; on Debian/Ubuntu, run: make install-shellcheck-linux
make[1]: Leaving directory '/home/sameer/Public/Shared/Work/Projects/OpenEdAI'
```

## make test-ci-all
```txt
make[1]: Entering directory '/home/sameer/Public/Shared/Work/Projects/OpenEdAI'
make test-health-contract
make[2]: Entering directory '/home/sameer/Public/Shared/Work/Projects/OpenEdAI'
go test ./internal/config -run 'TestLoadRejectsNegativeHealthDegradedLatency|TestLoadFallsBackForMalformedHealthDegradedLatency' -count=1
2026/05/29 14:54:36.497450 cmd_run.go:848: WARNING: XAUTHORITY environment value is not a clean path: "/run/xrdp/1000/Xauthority"
ok  	openedai-gateway/internal/config	0.003s
go test ./tests/integration -run 'TestHealthzContract|TestGatewayStartupRejectsNegativeHealthDegradedLatency|TestIntegrationStrictBackends' -count=1
2026/05/29 14:54:36.722975 cmd_run.go:848: WARNING: XAUTHORITY environment value is not a clean path: "/run/xrdp/1000/Xauthority"
ok  	openedai-gateway/tests/integration	0.452s
make[2]: Leaving directory '/home/sameer/Public/Shared/Work/Projects/OpenEdAI'
INTEGRATION_STRICT_BACKENDS=1 go test ./tests/integration -count=1
2026/05/29 14:54:37.781698 cmd_run.go:848: WARNING: XAUTHORITY environment value is not a clean path: "/run/xrdp/1000/Xauthority"
ok  	openedai-gateway/tests/integration	0.486s
make[1]: Leaving directory '/home/sameer/Public/Shared/Work/Projects/OpenEdAI'
```

## make smoke-gateway-auth
```txt
make[1]: Entering directory '/home/sameer/Public/Shared/Work/Projects/OpenEdAI'
bash scripts/ci/smoke_gateway_auth.sh
[smoke-auth] GATEWAY_TEST_API_KEY is not set; bootstrapping temporary admin key
[smoke-auth] bootstrapped temporary admin key id=a2e4ceb9-4d55-464c-889d-ef9b325020c9
[smoke-auth] running authenticated local smoke checks
[smoke] building gateway binary
2026/05/29 14:54:38.871342 cmd_run.go:848: WARNING: XAUTHORITY environment value is not a clean path: "/run/xrdp/1000/Xauthority"
[smoke] restarting user service
[smoke] waiting for /livez
curl: (7) Failed to connect to 127.0.0.1 port 8380 after 0 ms: Couldn't connect to server
[smoke][ok] /livez=200 /healthz=200 unauthorized_usage=401
[smoke][ok] authorized_usage=200
make[1]: Leaving directory '/home/sameer/Public/Shared/Work/Projects/OpenEdAI'
```

## Service Status Snapshot
```txt
● openedai-gateway.service - OpenEdAI Gateway (Go) - User Service
     Loaded: loaded (/home/sameer/.config/systemd/user/openedai-gateway.service; enabled; preset: enabled)
     Active: active (running) since Fri 2026-05-29 14:54:39 CEST; 1s ago
   Main PID: 1973825 (openedai-gatewa)
      Tasks: 14 (limit: 153548)
     Memory: 10.4M (peak: 10.7M)
        CPU: 20ms
     CGroup: /user.slice/user-1000.slice/user@1000.service/app.slice/openedai-gateway.service
             └─1973825 /home/sameer/Public/Shared/Work/Projects/OpenEdAI/openedai-gateway

May 29 14:54:39 promaxgb10-6116 openedai-gateway[1973825]: [GIN-debug] POST   /v1/management/api-keys   --> openedai-gateway/internal/api.(*Server).createAPIKey-fm (6 handlers)
May 29 14:54:39 promaxgb10-6116 openedai-gateway[1973825]: [GIN-debug] POST   /v1/management/api-keys/:id/revoke --> openedai-gateway/internal/api.(*Server).revokeAPIKey-fm (6 handlers)
May 29 14:54:39 promaxgb10-6116 openedai-gateway[1973825]: [GIN-debug] POST   /v1/management/api-keys/:id/rotate --> openedai-gateway/internal/api.(*Server).rotateAPIKey-fm (6 handlers)
May 29 14:54:39 promaxgb10-6116 openedai-gateway[1973825]: 2026/05/29 14:54:39 health policy: degraded_latency_ms=2000 critical_dependencies=[elasticsearch litellm postgres redis]
May 29 14:54:39 promaxgb10-6116 openedai-gateway[1973825]: 2026/05/29 14:54:39 gateway listening on 0.0.0.0:8380
May 29 14:54:40 promaxgb10-6116 openedai-gateway[1973825]: [GIN] 2026/05/29 - 14:54:40 | 200 |      19.616µs |       127.0.0.1 | GET      "/livez"
May 29 14:54:40 promaxgb10-6116 openedai-gateway[1973825]: [GIN] 2026/05/29 - 14:54:40 | 200 |       20.08µs |       127.0.0.1 | GET      "/livez"
May 29 14:54:40 promaxgb10-6116 openedai-gateway[1973825]: [GIN] 2026/05/29 - 14:54:40 | 200 |  201.645847ms |       127.0.0.1 | GET      "/healthz"
May 29 14:54:40 promaxgb10-6116 openedai-gateway[1973825]: [GIN] 2026/05/29 - 14:54:40 | 401 |      37.152µs |       127.0.0.1 | GET      "/v1/management/usage"
May 29 14:54:40 promaxgb10-6116 openedai-gateway[1973825]: [GIN] 2026/05/29 - 14:54:40 | 200 |    6.099396ms |       127.0.0.1 | GET      "/v1/management/usage"
```

## Notes
- This report enforces authenticated management smoke checks via GATEWAY_TEST_API_KEY.
- If GATEWAY_TEST_API_KEY is missing or invalid, smoke auth may bootstrap a temporary admin key for local validation.
