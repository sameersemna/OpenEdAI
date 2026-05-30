package middleware

import (
	"context"
	"net/http"
	"sync"
	"sync/atomic"

	"github.com/gin-gonic/gin"
)

type RequestLifecycle struct {
	wg           sync.WaitGroup
	shuttingDown atomic.Bool
}

func NewRequestLifecycle() *RequestLifecycle {
	return &RequestLifecycle{}
}

func (l *RequestLifecycle) StartShutdown() {
	l.shuttingDown.Store(true)
}

func (l *RequestLifecycle) Wait(ctx context.Context) error {
	done := make(chan struct{})
	go func() {
		l.wg.Wait()
		close(done)
	}()

	select {
	case <-done:
		return nil
	case <-ctx.Done():
		return ctx.Err()
	}
}

func InFlightRequestMiddleware(lifecycle *RequestLifecycle) gin.HandlerFunc {
	return func(c *gin.Context) {
		if lifecycle.shuttingDown.Load() {
			c.AbortWithStatusJSON(http.StatusServiceUnavailable, gin.H{
				"error": gin.H{"message": "Gateway is shutting down", "type": "server_error"},
			})
			return
		}

		lifecycle.wg.Add(1)
		defer lifecycle.wg.Done()

		c.Next()
	}
}
