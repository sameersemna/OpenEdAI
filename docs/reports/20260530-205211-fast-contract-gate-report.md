# Fast Contract Gate Report (20260530-205211)

- Status: PASS
- Command: make test-ci-fast-contracts

## Output
```text
make[1]: Entering directory '/home/sameer/Public/Shared/Work/Projects/OpenEdAI'
[contracts][warn] API_KEY_HASH_PEPPER is not set; some focused integration contracts can skip.
go test ./internal/config -run 'TestLoadRejectsNegativeHealthDegradedLatency|TestLoadFallsBackForMalformedHealthDegradedLatency|TestLoadStrictValidationRejectsUnsafeDefaultPepper|TestLoadRejectsMalformedServiceURLs|TestLoadRejectsNonPositiveRequestTimeout' -count=1
2026/05/30 20:52:11.258383 cmd_run.go:848: WARNING: XAUTHORITY environment value is not a clean path: "/run/xrdp/1000/Xauthority"
ok  	openedai-gateway/internal/config	0.004s
go test ./tests/integration -run 'TestHealthzContract|TestGatewayStartupRejectsNegativeHealthDegradedLatency|TestIntegrationStrictBackends' -count=1
2026/05/30 20:52:11.493521 cmd_run.go:848: WARNING: XAUTHORITY environment value is not a clean path: "/run/xrdp/1000/Xauthority"
ok  	openedai-gateway/tests/integration	0.283s
go test ./internal/api -run 'TestManagementRoute' -count=1
2026/05/30 20:52:12.447306 cmd_run.go:848: WARNING: XAUTHORITY environment value is not a clean path: "/run/xrdp/1000/Xauthority"
ok  	openedai-gateway/internal/api	0.012s
go test ./tests/integration -run 'TestProxyFlowWithSplitKey/(usage_summary_.*fallback|usage_summary_.*boundary_validation)' -count=1 -v
2026/05/30 20:52:13.062749 cmd_run.go:848: WARNING: XAUTHORITY environment value is not a clean path: "/run/xrdp/1000/Xauthority"
=== RUN   TestProxyFlowWithSplitKey
    proxy_flow_test.go:18: API_KEY_HASH_PEPPER is required
--- SKIP: TestProxyFlowWithSplitKey (0.00s)
PASS
ok  	openedai-gateway/tests/integration	0.009s
make[1]: Leaving directory '/home/sameer/Public/Shared/Work/Projects/OpenEdAI'
```
