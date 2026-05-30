package middleware

import (
	"net/http"
	"strconv"
	"strings"

	"github.com/coreos/go-systemd/v22/journal"
	"github.com/gin-gonic/gin"
)

const requestLogMetricsContextKey = "request_log_metrics"
const requestLogErrorContextKey = "request_log_error"

type RequestLogMetrics struct {
	UpstreamLatencyMS int64
	TokensUsed        int
}

type RequestLogError struct {
	Type string
	Code string
}

type journalSender func(string, journal.Priority, map[string]string) error

var sendJournalEntry journalSender = journal.Send

func SetRequestLogMetrics(c *gin.Context, metrics RequestLogMetrics) {
	c.Set(requestLogMetricsContextKey, metrics)
}

func SetRequestLogError(c *gin.Context, requestErr RequestLogError) {
	c.Set(requestLogErrorContextKey, requestErr)
}

func JournaldRequestLogMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		c.Next()

		fields := map[string]string{
			"OPENEDAI_HTTP_METHOD":  c.Request.Method,
			"OPENEDAI_REQUEST_PATH": c.Request.URL.Path,
			"OPENEDAI_REMOTE_IP":    c.ClientIP(),
			"OPENEDAI_STATUS_CODE":  strconv.Itoa(c.Writer.Status()),
		}

		if apiKey := GetAPIKeyFromContext(c); apiKey != nil {
			fields["OPENEDAI_KEY_ID"] = apiKey.ID
		}

		requestID := c.Writer.Header().Get("X-Request-ID")
		if requestID == "" {
			requestID = c.GetHeader("X-Request-ID")
		}
		if requestID != "" {
			fields["OPENEDAI_REQUEST_ID"] = requestID
		}

		if metrics, ok := getRequestLogMetrics(c); ok {
			if metrics.UpstreamLatencyMS > 0 {
				fields["OPENEDAI_UPSTREAM_LATENCY_MS"] = strconv.FormatInt(metrics.UpstreamLatencyMS, 10)
			}
			if metrics.TokensUsed > 0 {
				fields["OPENEDAI_TOKENS"] = strconv.Itoa(metrics.TokensUsed)
				fields["OPENEDAI_TOKENS_USED"] = strconv.Itoa(metrics.TokensUsed)
			}
		}

		if requestErr, ok := getRequestLogError(c); ok {
			if requestErr.Type != "" {
				fields["OPENEDAI_ERROR_TYPE"] = requestErr.Type
			}
			if requestErr.Code != "" {
				fields["OPENEDAI_ERROR_CODE"] = requestErr.Code
			}
		}

		if err := sendJournalEntry(journalMessage(c), journalPriority(c.Writer.Status()), fields); err != nil {
			c.Error(err)
		}
	}
}

func getRequestLogMetrics(c *gin.Context) (RequestLogMetrics, bool) {
	v, ok := c.Get(requestLogMetricsContextKey)
	if !ok {
		return RequestLogMetrics{}, false
	}
	metrics, ok := v.(RequestLogMetrics)
	if !ok {
		return RequestLogMetrics{}, false
	}
	return metrics, true
}

func getRequestLogError(c *gin.Context) (RequestLogError, bool) {
	v, ok := c.Get(requestLogErrorContextKey)
	if !ok {
		return RequestLogError{}, false
	}
	requestErr, ok := v.(RequestLogError)
	if !ok {
		return RequestLogError{}, false
	}
	return requestErr, true
}

func journalMessage(c *gin.Context) string {
	var builder strings.Builder
	builder.WriteString(c.Request.Method)
	builder.WriteByte(' ')
	builder.WriteString(c.Request.URL.Path)
	builder.WriteString(" -> ")
	builder.WriteString(strconv.Itoa(c.Writer.Status()))
	return builder.String()
}

func journalPriority(statusCode int) journal.Priority {
	switch {
	case statusCode >= http.StatusInternalServerError:
		return journal.PriErr
	case statusCode >= http.StatusBadRequest:
		return journal.PriWarning
	default:
		return journal.PriInfo
	}
}
