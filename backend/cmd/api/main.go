// Command api runs the pennyWise HTTP API.
package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"
	_ "time/tzdata" // IANA time zones, also inside the distroless image

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
	"github.com/hibiken/asynq"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/collectors"

	"pennywise/backend/internal/audit"
	"pennywise/backend/internal/auth"
	"pennywise/backend/internal/config"
	"pennywise/backend/internal/datasync"
	"pennywise/backend/internal/exports"
	"pennywise/backend/internal/fx"
	"pennywise/backend/internal/httpapi"
	"pennywise/backend/internal/mail"
	"pennywise/backend/internal/notify"
	"pennywise/backend/internal/platform/postgres"
	"pennywise/backend/internal/platform/redis"
	"pennywise/backend/internal/ratelimit"
	"pennywise/backend/internal/receipts"
	"pennywise/backend/internal/reports"
	"pennywise/backend/internal/storage"
)

// Limits that apply to every request (feature routes add stricter ones).
var (
	ruleIP   = ratelimit.Rule{Name: "ip", Limit: 3000, Window: time.Minute}
	ruleUser = ratelimit.Rule{Name: "user", Limit: 600, Window: time.Minute}
)

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	redis.UseSlog(logger)
	if err := run(logger); err != nil {
		logger.Error("api stopped", "err", err)
		os.Exit(1)
	}
}

func run(logger *slog.Logger) error {
	cfg, err := config.Load()
	if err != nil {
		return err
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	db, err := postgres.Open(ctx, cfg.DatabaseURL)
	if err != nil {
		return err
	}
	defer db.Close()

	rdb, err := redis.Open(ctx, cfg.RedisURL)
	if err != nil {
		return err
	}
	defer rdb.Close()

	jwtIssuer, err := auth.NewJWTIssuer(cfg.JWTSecret, cfg.AccessTokenTTL)
	if err != nil {
		return err
	}
	var google auth.GoogleVerifier
	if len(cfg.GoogleClientIDs) > 0 {
		google = auth.NewGoogleVerifier(cfg.GoogleClientIDs)
	} else {
		logger.Warn("GOOGLE_CLIENT_IDS not set: Google sign-in is disabled")
	}
	redisOpt, err := asynq.ParseRedisURI(cfg.RedisURL)
	if err != nil {
		return err
	}
	queue := asynq.NewClient(redisOpt)
	defer queue.Close()
	enqueuer := notify.NewEnqueuer(queue)

	authSvc := auth.NewService(db, jwtIssuer, google, mail.LogMailer{Logger: logger},
		auth.Config{
			RefreshTTL:    cfg.RefreshTokenTTL,
			LinkBase:      cfg.LinkBase,
			OnUserCreated: datasync.SeedDefaultCategories,
			ChangeBaseCurrency: func(ctx context.Context, id uuid.UUID, c string) error {
				err := fx.ChangeBase(ctx, db, queue, id, c)
				if errors.Is(err, fx.ErrRecalculating) {
					return auth.ErrBaseCurrencyBusy
				}
				return err
			},
		}, logger)
	limiter := ratelimit.New(rdb)
	auditLog := audit.New(db, logger)
	authHandler := auth.NewHandler(authSvc, limiter, logger).WithAudit(auditLog)
	userIDOf := func(r *http.Request) uuid.UUID { return auth.UserID(r.Context()) }
	// Every signed-in route: the token check, then a per-user limit
	// (generous: a full sync is a few requests).
	perUser := ratelimit.Middleware(limiter, ruleUser, func(r *http.Request) string { return userIDOf(r).String() }, logger)
	requireAuth := func(next http.Handler) http.Handler { return authHandler.RequireAuth(perUser(next)) }

	syncSvc := datasync.NewService(db, logger)
	// New spending may cross a budget level: let the worker check.
	syncSvc.OnApplied = enqueuer.EnqueueBudgetCheck
	syncHandler := datasync.NewHandler(syncSvc, requireAuth, userIDOf, logger)
	devicesHandler := notify.NewDevicesHandler(db, requireAuth, userIDOf, logger)
	fxHandler := fx.NewHandler(db, requireAuth, logger)

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
	} else {
		logger.Warn("R2_BUCKET not set: receipt upload and export are disabled")
	}
	exportsHandler := exports.NewHandler(exportSvc, limiter, requireAuth, userIDOf, logger).WithAudit(auditLog)
	reportsHandler := reports.NewHandler(db, rdb, requireAuth, userIDOf, logger)
	receiptsHandler := receipts.NewHandler(receiptSvc, limiter, requireAuth, userIDOf, logger)

	reg := prometheus.NewRegistry()
	reg.MustRegister(collectors.NewGoCollector(), collectors.NewProcessCollector(collectors.ProcessCollectorOpts{}))

	srv := &http.Server{
		Addr: cfg.HTTPAddr,
		Handler: httpapi.NewRouter(httpapi.Deps{
			Logger:   logger,
			Registry: reg,
			Checks: map[string]httpapi.Pinger{
				"postgres": db,
				"redis": httpapi.PingFunc(func(ctx context.Context) error {
					return rdb.Ping(ctx).Err()
				}),
			},
			// Per IP over all of /v1. High, because many phones can share one
			// carrier IP (CGNAT); auth routes have their own strict limits.
			V1Middleware: []func(http.Handler) http.Handler{
				ratelimit.Middleware(limiter, ruleIP, ratelimit.ClientIP, logger),
			},
			V1: []func(chi.Router){authHandler.Routes, syncHandler.Routes, devicesHandler.Routes, fxHandler.Routes, receiptsHandler.Routes, reportsHandler.Routes, exportsHandler.Routes},
		}),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       15 * time.Second,
		WriteTimeout:      35 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	errCh := make(chan error, 1)
	go func() {
		logger.Info("api listening", "addr", cfg.HTTPAddr, "env", cfg.Env)
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			errCh <- err
		}
		close(errCh)
	}()

	select {
	case err := <-errCh:
		return err
	case <-ctx.Done():
	}

	logger.Info("api shutting down")
	shutdownCtx, cancel := context.WithTimeout(context.Background(), cfg.ShutdownTimeout)
	defer cancel()
	return srv.Shutdown(shutdownCtx)
}
