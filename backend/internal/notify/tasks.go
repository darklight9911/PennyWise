package notify

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/hibiken/asynq"
)

// TaskCheckBudgets asks the worker to check one user's budgets.
const TaskCheckBudgets = "budgets:check"

type checkPayload struct {
	UserID uuid.UUID `json:"user_id"`
}

// Enqueuer queues budget checks. Within a short window, a user's repeated
// pushes become ONE check (asynq task id), so a burst of syncs is cheap.
type Enqueuer struct {
	client *asynq.Client
	window time.Duration
}

// NewEnqueuer creates an enqueuer on the given asynq client.
func NewEnqueuer(client *asynq.Client) *Enqueuer {
	return &Enqueuer{client: client, window: 30 * time.Second}
}

// EnqueueBudgetCheck queues a check a few seconds from now. A duplicate in
// the same window is not an error.
func (e *Enqueuer) EnqueueBudgetCheck(ctx context.Context, userID uuid.UUID) error {
	payload, _ := json.Marshal(checkPayload{UserID: userID})
	slot := time.Now().Truncate(e.window).Unix()
	_, err := e.client.EnqueueContext(ctx,
		asynq.NewTask(TaskCheckBudgets, payload),
		asynq.TaskID(fmt.Sprintf("budgets:%s:%d", userID, slot)),
		asynq.ProcessIn(5*time.Second),
		asynq.MaxRetry(5),
		asynq.Timeout(time.Minute),
		asynq.Retention(time.Hour),
	)
	if errors.Is(err, asynq.ErrTaskIDConflict) {
		return nil
	}
	return err
}

// HandleCheckBudgets is the worker side of TaskCheckBudgets.
func (b *BudgetChecker) HandleCheckBudgets(ctx context.Context, t *asynq.Task) error {
	var p checkPayload
	if err := json.Unmarshal(t.Payload(), &p); err != nil || p.UserID == uuid.Nil {
		return fmt.Errorf("bad payload: %w", asynq.SkipRetry)
	}
	alerts, err := b.Check(ctx, p.UserID)
	if err != nil {
		return err
	}
	if len(alerts) > 0 {
		b.logger.InfoContext(ctx, "budget alerts sent", "count", len(alerts))
	}
	return nil
}
