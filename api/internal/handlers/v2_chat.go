package handlers

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"time"

	"github.com/labstack/echo/v4"

	"github.com/donwb/beach/api/internal/chat"
)

// chatTimeout bounds one question end to end. A question is two or three
// model calls plus tool reads; the Apple client waits 60s, so the server
// gives up first and answers with a 504 the client can explain.
const chatTimeout = 50 * time.Second

// HandleV2Chat answers one natural-language question over the prediction
// engine. POST /api/v2/chat, body chat.Request, reply chat.Response.
// Route-level auth (chatKeyAuth) has already run.
func HandleV2Chat(runner *chat.Runner) echo.HandlerFunc {
	return func(c echo.Context) error {
		var req chat.Request
		if err := c.Bind(&req); err != nil {
			return c.JSON(http.StatusBadRequest, map[string]string{"error": "invalid JSON body"})
		}
		if err := req.Validate(); err != nil {
			return c.JSON(http.StatusBadRequest, map[string]string{"error": err.Error()})
		}
		if runner == nil {
			return c.JSON(http.StatusServiceUnavailable, map[string]string{"error": "chat not configured"})
		}

		ctx, cancel := context.WithTimeout(c.Request().Context(), chatTimeout)
		defer cancel()

		resp, err := runner.Run(ctx, req)
		if err != nil {
			if errors.Is(err, context.DeadlineExceeded) || errors.Is(ctx.Err(), context.DeadlineExceeded) {
				slog.Warn("chat timed out", "err", err)
				return c.JSON(http.StatusGatewayTimeout, map[string]string{"error": "the outlook took too long to answer"})
			}
			slog.Error("chat upstream failed", "err", err)
			return c.JSON(http.StatusBadGateway, map[string]string{"error": "chat upstream failed"})
		}
		return c.JSON(http.StatusOK, resp)
	}
}
