# Local Release Smoke Report (20260529-145407)

## Scope
- Repository: OpenEdAI
- Host: promaxgb10-6116
- Generated: 2026-05-29T14:54:11+02:00

## Checklist Results
- make ci-local-status: 0
- make test-ci-all: 0
- make smoke-gateway-local: 0
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
2026/05/29 14:54:07.870152 cmd_run.go:848: WARNING: XAUTHORITY environment value is not a clean path: "/run/xrdp/1000/Xauthority"
ok  	openedai-gateway/internal/config	0.003s
go test ./tests/integration -run 'TestHealthzContract|TestGatewayStartupRejectsNegativeHealthDegradedLatency|TestIntegrationStrictBackends' -count=1
2026/05/29 14:54:08.100486 cmd_run.go:848: WARNING: XAUTHORITY environment value is not a clean path: "/run/xrdp/1000/Xauthority"
ok  	openedai-gateway/tests/integration	0.464s
make[2]: Leaving directory '/home/sameer/Public/Shared/Work/Projects/OpenEdAI'
INTEGRATION_STRICT_BACKENDS=1 go test ./tests/integration -count=1
2026/05/29 14:54:09.124956 cmd_run.go:848: WARNING: XAUTHORITY environment value is not a clean path: "/run/xrdp/1000/Xauthority"
ok  	openedai-gateway/tests/integration	0.458s
make[1]: Leaving directory '/home/sameer/Public/Shared/Work/Projects/OpenEdAI'
```

## make smoke-gateway-local
```txt
make[1]: Entering directory '/home/sameer/Public/Shared/Work/Projects/OpenEdAI'
bash scripts/ci/smoke_gateway.sh
[smoke] building gateway binary
2026/05/29 14:54:10.108141 cmd_run.go:848: WARNING: XAUTHORITY environment value is not a clean path: "/run/xrdp/1000/Xauthority"
[smoke] restarting user service
[smoke] waiting for /livez
curl: (7) Failed to connect to 127.0.0.1 port 8380 after 0 ms: Couldn't connect to server
[smoke][ok] /livez=200 /healthz=200 unauthorized_usage=401
[smoke][skip] set GATEWAY_TEST_API_KEY to include authorized management check
make[1]: Leaving directory '/home/sameer/Public/Shared/Work/Projects/OpenEdAI'
```

## Service Status Snapshot
```txt
● openedai-gateway.service - OpenEdAI Gateway (Go) - User Service
     Loaded: loaded (/home/sameer/.config/systemd/user/openedai-gateway.service; enabled; preset: enabled)
     Active: active (running) since Fri 2026-05-29 14:54:10 CEST; 1s ago
   Main PID: 1969830 (openedai-gatewa)
      Tasks: 12 (limit: 153548)
     Memory: 9.8M (peak: 10.4M)
        CPU: 22ms
     CGroup: /user.slice/user-1000.slice/user@1000.service/app.slice/openedai-gateway.service
             └─1969830 /home/sameer/Public/Shared/Work/Projects/OpenEdAI/openedai-gateway

May 29 14:54:10 promaxgb10-6116 openedai-gateway[1969830]: [GIN-debug] GET    /v1/management/usage      --> openedai-gateway/internal/api.(*Server).usageSummary-fm (5 handlers)
May 29 14:54:10 promaxgb10-6116 openedai-gateway[1969830]: [GIN-debug] POST   /v1/management/api-keys   --> openedai-gateway/internal/api.(*Server).createAPIKey-fm (6 handlers)
May 29 14:54:10 promaxgb10-6116 openedai-gateway[1969830]: [GIN-debug] POST   /v1/management/api-keys/:id/revoke --> openedai-gateway/internal/api.(*Server).revokeAPIKey-fm (6 handlers)
May 29 14:54:10 promaxgb10-6116 openedai-gateway[1969830]: [GIN-debug] POST   /v1/management/api-keys/:id/rotate --> openedai-gateway/internal/api.(*Server).rotateAPIKey-fm (6 handlers)
May 29 14:54:10 promaxgb10-6116 openedai-gateway[1969830]: 2026/05/29 14:54:10 health policy: degraded_latency_ms=2000 critical_dependencies=[elasticsearch litellm postgres redis]
May 29 14:54:10 promaxgb10-6116 openedai-gateway[1969830]: 2026/05/29 14:54:10 gateway listening on 0.0.0.0:8380
May 29 14:54:11 promaxgb10-6116 openedai-gateway[1969830]: [GIN] 2026/05/29 - 14:54:11 | 200 |      21.312µs |       127.0.0.1 | GET      "/livez"
May 29 14:54:11 promaxgb10-6116 openedai-gateway[1969830]: [GIN] 2026/05/29 - 14:54:11 | 200 |      28.688µs |       127.0.0.1 | GET      "/livez"
May 29 14:54:11 promaxgb10-6116 openedai-gateway[1969830]: [GIN] 2026/05/29 - 14:54:11 | 200 |   201.34096ms |       127.0.0.1 | GET      "/healthz"
May 29 14:54:11 promaxgb10-6116 openedai-gateway[1969830]: [GIN] 2026/05/29 - 14:54:11 | 401 |      31.024µs |       127.0.0.1 | GET      "/v1/management/usage"
```

## Notes
- shellcheck may be absent locally; script lint remains covered by CI workflow.
- Authorized management endpoint smoke check is optional and requires GATEWAY_TEST_API_KEY.
