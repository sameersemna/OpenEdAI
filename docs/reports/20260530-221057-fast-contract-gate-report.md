# Fast Contract Gate Report (20260530-221057)

- Status: PASS
- Command: make test-ci-fast-contracts

## Output
```text
make[3]: Entering directory '/home/sameer/Public/Shared/Work/Projects/OpenEdAI'
bash scripts/ci/check_contract_gate_env.sh fast
[contracts][warn] API_KEY_HASH_PEPPER is not set; some focused integration contracts can skip.
go test ./internal/config -run 'TestLoadRejectsNegativeHealthDegradedLatency|TestLoadFallsBackForMalformedHealthDegradedLatency|TestLoadStrictValidationRejectsUnsafeDefaultPepper|TestLoadRejectsMalformedServiceURLs|TestLoadRejectsNonPositiveRequestTimeout' -count=1
2026/05/30 22:10:57.749375 cmd_run.go:848: WARNING: XAUTHORITY environment value is not a clean path: "/run/xrdp/1000/Xauthority"
ok  	openedai-gateway/internal/config	0.004s
go test ./tests/integration -run 'TestHealthzContract|TestGatewayStartupRejectsNegativeHealthDegradedLatency|TestIntegrationStrictBackends' -count=1
2026/05/30 22:10:57.967103 cmd_run.go:848: WARNING: XAUTHORITY environment value is not a clean path: "/run/xrdp/1000/Xauthority"
ok  	openedai-gateway/tests/integration	0.447s
go test ./internal/api -run 'TestManagementRoute' -count=1
2026/05/30 22:10:59.103916 cmd_run.go:848: WARNING: XAUTHORITY environment value is not a clean path: "/run/xrdp/1000/Xauthority"
ok  	openedai-gateway/internal/api	0.009s
go test ./tests/integration -run 'TestProxyFlowWithSplitKey/(usage_summary_.*fallback|usage_summary_.*boundary_validation)' -count=1 -v
2026/05/30 22:10:59.737302 cmd_run.go:848: WARNING: XAUTHORITY environment value is not a clean path: "/run/xrdp/1000/Xauthority"
=== RUN   TestProxyFlowWithSplitKey
    proxy_flow_test.go:18: API_KEY_HASH_PEPPER is required
--- SKIP: TestProxyFlowWithSplitKey (0.00s)
PASS
ok  	openedai-gateway/tests/integration	0.011s
make[3]: Leaving directory '/home/sameer/Public/Shared/Work/Projects/OpenEdAI'
```
