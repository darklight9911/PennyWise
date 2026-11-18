// Command worker runs background jobs (recurring transactions, alerts,
// exchange rates, exports) from the Redis-backed asynq queue.
package main

import (
	"context"
	"fmt"
	"log/slog"
	"os"
	"time"

	"github.com/google/uuid"
	"github.com/hibiken/asynq"

	"pennywise/backend/internal/account"
	"pennywise/backend/internal/audit"
	"pennywise/backend/internal/config"
	"pennywise/backend/internal/exports"
	"pennywise/backend/internal/fx"
	"pennywise/backend/internal/notify"
	"pennywise/backend/internal/platform/postgres"
	"pennywise/backend/internal/platform/redis"
	"pennywise/backend/internal/receipts"
	"pennywise/backend/internal/recurring"
	"pennywise/backend/internal/storage"
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
	cfg, err := config.LoadWorker()
	if err != nil {
		return err
	}
	redisOpt, err := asynq.ParseRedisURI(cfg.RedisURL)
	if err != nil {
		return err
	}
	db, err := postgres.Open(context.Background(), cfg.DatabaseURL)
	if err != nil {
		return err
	}
	defer db.Close()
	// Real push (Firebase) needs a Firebase project; until then messages
	// are written to the log.
	sender := notify.LogSender{Logger: logger}
	budgets := notify.NewBudgetChecker(db, sender, logger)

	queue := asynq.NewClient(redisOpt)
	defer queue.Close()
	gen := recurring.NewGenerator(db, func(ctx context.Context, userID uuid.UUID, m recurring.Message) {
		notify.SendToUser(ctx, db, sender, logger, userID, notify.Message{Title: m.Title, Body: m.Body, Data: m.Data})
	}, logger)
	// New bills may cross a budget level.
	gen.OnCreated = notify.NewEnqueuer(queue).EnqueueBudgetCheck

	// Every 15 minutes: create due recurring transactions, send reminders.
	scheduler := asynq.NewScheduler(redisOpt, &asynq.SchedulerOpts{Logger: asynqLogger{logger}})
	if _, err := scheduler.Register("*/15 * * * *", asynq.NewTask(recurring.TaskRunAll, nil),
		asynq.Unique(14*time.Minute), asynq.Timeout(10*time.Minute)); err != nil {
		return err
	}
	// Every 6 hours: new exchange rates (ECB publishes once a working day,
	// around 16:00 CET), then base amounts that waited for them.
	if _, err := scheduler.Register("15 */6 * * *", asynq.NewTask(fx.TaskRefresh, nil),
		asynq.Unique(5*time.Hour), asynq.Timeout(20*time.Minute), asynq.MaxRetry(3)); err != nil {
		return err
	}
	store, err := storage.Open(storage.R2Config(cfg.R2))
	if err != nil {
		return err
	}
	var (
		receiptSvc *receipts.Service
		exportSvc  *exports.Service
	)
	if store != nil {
		receiptSvc = receipts.NewService(db, store, logger)
		exportSvc = exports.NewService(db, store, queue, logger)
		// Nightly: export files older than 7 days.
		if _, err := scheduler.Register("45 3 * * *", asynq.NewTask(exports.TaskCleanup, nil),
			asynq.Unique(23*time.Hour), asynq.Timeout(30*time.Minute)); err != nil {
			return err
		}
		// Nightly: unfinished uploads, receipts of deleted transactions,
		// files of deleted receipts.
		if _, err := scheduler.Register("30 3 * * *", asynq.NewTask(receipts.TaskCleanup, nil),
			asynq.Unique(23*time.Hour), asynq.Timeout(30*time.Minute)); err != nil {
			return err
		}
	}
	purger := account.NewPurger(db, store, queue, logger)
	if _, err := scheduler.Register("15 4 * * *", asynq.NewTask(account.TaskSweep, nil),
		asynq.Unique(23*time.Hour), asynq.Timeout(30*time.Minute)); err != nil {
		return err
	}
	auditLog := audit.New(db, logger)
	if _, err := scheduler.Register("0 4 * * *", asynq.NewTask(audit.TaskPrune, nil),
		asynq.Unique(23*time.Hour), asynq.Timeout(10*time.Minute)); err != nil {
		return err
	}
	if err := scheduler.Start(); err != nil {
		return err
	}
	defer scheduler.Shutdown()

	srv := asynq.NewServer(redisOpt, asynq.Config{
		Concurrency: 5,
		Queues:      map[string]int{"critical": 6, "default": 3, "low": 1},
		Logger:      asynqLogger{logger},
	})

	mux := asynq.NewServeMux()
	mux.HandleFunc(notify.TaskCheckBudgets, budgets.HandleCheckBudgets)
	mux.HandleFunc(recurring.TaskRunAll, gen.HandleRunAll)
	rates := fx.NewService(db, fx.NewFrankfurter(cfg.FXAPIURL), logger)
	mux.HandleFunc(fx.TaskRefresh, rates.HandleRefresh)
	mux.HandleFunc(fx.TaskRebase, rates.HandleRebase)
	mux.HandleFunc(audit.TaskPrune, auditLog.HandlePrune)
	mux.HandleFunc(account.TaskPurge, purger.HandlePurge)
	mux.HandleFunc(account.TaskSweep, purger.HandleSweep)
	if receiptSvc != nil {
		mux.HandleFunc(receipts.TaskCleanup, receiptSvc.HandleCleanup)
		mux.HandleFunc(exports.TaskBuild, exportSvc.HandleBuild)
		mux.HandleFunc(exports.TaskCleanup, exportSvc.HandleCleanup)
	}
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
