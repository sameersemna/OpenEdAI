# Fast Contract Gate Report (20260531-101028)

- Status: PASS
- Command: make test-ci-fast-contracts

## Output
```text
make[2]: Entering directory '/home/sameer/Public/Shared/Work/Projects/OpenEdAI'
bash scripts/ci/check_contract_gate_env.sh fast
[contracts][warn] API_KEY_HASH_PEPPER is not set; some focused integration contracts can skip.
go test ./internal/config -run 'TestLoadRejectsNegativeHealthDegradedLatency|TestLoadFallsBackForMalformedHealthDegradedLatency|TestLoadStrictValidationRejectsUnsafeDefaultPepper|TestLoadRejectsMalformedServiceURLs|TestLoadRejectsNonPositiveRequestTimeout' -count=1
2026/05/31 10:10:28.752025 cmd_run.go:848: WARNING: XAUTHORITY environment value is not a clean path: "/run/xrdp/1000/Xauthority"
ok  	openedai-gateway/internal/config	0.003s
go test ./tests/integration -run 'TestHealthzContract|TestGatewayStartupRejectsNegativeHealthDegradedLatency|TestIntegrationStrictBackends' -count=1
2026/05/31 10:10:29.003828 cmd_run.go:848: WARNING: XAUTHORITY environment value is not a clean path: "/run/xrdp/1000/Xauthority"
ok  	openedai-gateway/tests/integration	0.490s
go test ./internal/api -run 'TestManagementRoute' -count=1
2026/05/31 10:10:30.188259 cmd_run.go:848: WARNING: XAUTHORITY environment value is not a clean path: "/run/xrdp/1000/Xauthority"
ok  	openedai-gateway/internal/api	0.011s
go test ./tests/integration -run 'TestProxyFlowWithSplitKey/(usage_summary_.*fallback|usage_summary_.*boundary_validation)' -count=1 -v
2026/05/31 10:10:30.791421 cmd_run.go:848: WARNING: XAUTHORITY environment value is not a clean path: "/run/xrdp/1000/Xauthority"
=== RUN   TestProxyFlowWithSplitKey
    proxy_flow_test.go:18: API_KEY_HASH_PEPPER is required
--- SKIP: TestProxyFlowWithSplitKey (0.00s)
PASS
ok  	openedai-gateway/tests/integration	0.010s
make[2]: Leaving directory '/home/sameer/Public/Shared/Work/Projects/OpenEdAI'
```
