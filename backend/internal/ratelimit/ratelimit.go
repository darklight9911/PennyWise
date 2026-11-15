// Package ratelimit limits how often a key (IP, email, ...) may do something,
// using fixed time windows stored in Redis.
package ratelimit

import (
	"context"
	"fmt"
	"time"

	goredis "github.com/redis/go-redis/v9"
)

// Limiter counts attempts per key and window.
type Limiter struct {
	rdb    *goredis.Client
	prefix string
	now    func() time.Time
}

// New creates a limiter. All keys are stored under "rl:".
func New(rdb *goredis.Client) *Limiter {
	return &Limiter{rdb: rdb, prefix: "rl:", now: time.Now}
}

// Rule is "at most Limit attempts per Window".
type Rule struct {
	Name   string
	Limit  int64
	Window time.Duration
}

// Allow records one attempt for key under rule. It returns whether the
// attempt is allowed and, if not, how long until the window resets.
func (l *Limiter) Allow(ctx context.Context, rule Rule, key string) (bool, time.Duration, error) {
	now := l.now()
	windowStart := now.Truncate(rule.Window)
	redisKey := fmt.Sprintf("%s%s:%s:%d", l.prefix, rule.Name, key, windowStart.Unix())

	pipe := l.rdb.TxPipeline()
	incr := pipe.Incr(ctx, redisKey)
	pipe.ExpireNX(ctx, redisKey, rule.Window+time.Second)
	if _, err := pipe.Exec(ctx); err != nil {
		return false, 0, fmt.Errorf("ratelimit: %w", err)
	}
	if incr.Val() > rule.Limit {
		return false, windowStart.Add(rule.Window).Sub(now), nil
	}
	return true, 0, nil
}
