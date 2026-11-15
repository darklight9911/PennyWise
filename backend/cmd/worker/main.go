// Command worker runs background jobs (recurring transactions, alerts,
// exchange rates, exports) from the Redis-backed asynq queue.
package main

import (
	"context"
	"fmt"
	"log/slog"
	"os"

	"github.com/hibiken/asynq"

	"pennywise/backend/internal/config"
	"pennywise/backend/internal/platform/redis"
)

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	redis.UseSlog(logger)
	if err := run(logger); err != nil {
		logger.Error("worker stopped", "err", err)
		os.Exit(1)
	}
}

func run(logger *slog.Logger) error {
	cfg, err := config.Load()
	if err != nil {
		return err
	}
	redisOpt, err := asynq.ParseRedisURI(cfg.RedisURL)
	if err != nil {
		return err
	}

	srv := asynq.NewServer(redisOpt, asynq.Config{
		Concurrency: 5,
		Queues:      map[string]int{"critical": 6, "default": 3, "low": 1},
		Logger:      asynqLogger{logger},
	})

	mux := asynq.NewServeMux()
	// Job handlers are registered here in later milestones, e.g.:
	//   mux.HandleFunc(recurring.TaskRun, recurringHandler.Run)
	mux.HandleFunc("system:ping", func(ctx context.Context, t *asynq.Task) error {
		logger.InfoContext(ctx, "ping job received")
		return nil
	})

	logger.Info("worker starting", "env", cfg.Env)
	// Run blocks until SIGTERM/SIGINT, then waits for running jobs to finish.
	return srv.Run(mux)
}

// asynqLogger sends asynq's internal logs to slog.
type asynqLogger struct{ l *slog.Logger }

func (a asynqLogger) Debug(args ...any) { a.l.Debug("asynq", "detail", fmt.Sprint(args...)) }
func (a asynqLogger) Info(args ...any)  { a.l.Info("asynq", "detail", fmt.Sprint(args...)) }
func (a asynqLogger) Warn(args ...any)  { a.l.Warn("asynq", "detail", fmt.Sprint(args...)) }
func (a asynqLogger) Error(args ...any) { a.l.Error("asynq", "detail", fmt.Sprint(args...)) }
func (a asynqLogger) Fatal(args ...any) {
	a.l.Error("asynq fatal", "detail", fmt.Sprint(args...))
	os.Exit(1)
}
