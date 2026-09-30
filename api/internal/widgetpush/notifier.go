package widgetpush

import (
	"context"
	"errors"
	"log/slog"
	"sync"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/donwb/beach/api/internal/database"
	"github.com/donwb/beach/api/internal/models"
)

// Store is what the notifier needs from the database; the pool-backed
// implementation is the default and tests substitute a fake.
type Store interface {
	ListWidgetPushTokens(ctx context.Context) ([]models.WidgetPushToken, error)
	DeleteWidgetPushToken(ctx context.Context, token string) error
	MarkWidgetPushed(ctx context.Context, tokens []string, at time.Time) error
}

type poolStore struct{ pool *pgxpool.Pool }

func (s poolStore) ListWidgetPushTokens(ctx context.Context) ([]models.WidgetPushToken, error) {
	return database.ListWidgetPushTokens(ctx, s.pool)
}
func (s poolStore) DeleteWidgetPushToken(ctx context.Context, token string) error {
	return database.DeleteWidgetPushToken(ctx, s.pool, token)
}
func (s poolStore) MarkWidgetPushed(ctx context.Context, tokens []string, at time.Time) error {
	return database.MarkWidgetPushed(ctx, s.pool, tokens, at)
}

// Notifier coalesces status flips into widget pushes. A flip schedules a
// run after Debounce (one GIS poll can flip several ramps — one push
// covers them all); runs are at least MinInterval apart, and a flip during
// the quiet period schedules exactly one more run at its end. Best-effort
// throughout: nothing here can fail the ingester.
type Notifier struct {
	sender Sender
	store  Store
	log    *slog.Logger

	// Debounce is the wait after the first flip before pushing.
	Debounce time.Duration
	// MinInterval is the shortest gap between two push runs.
	MinInterval time.Duration

	mu        sync.Mutex
	timer     *time.Timer
	lastRun   time.Time
	pending   bool
	now       func() time.Time
	afterFunc func(time.Duration, func()) *time.Timer
}

// NewNotifier wires a Sender to the token table.
func NewNotifier(sender Sender, pool *pgxpool.Pool) *Notifier {
	return newNotifier(sender, poolStore{pool: pool})
}

func newNotifier(sender Sender, store Store) *Notifier {
	return &Notifier{
		sender:      sender,
		store:       store,
		log:         slog.Default().With("component", "widgetpush"),
		Debounce:    5 * time.Second,
		MinInterval: 60 * time.Second,
		now:         time.Now,
		afterFunc:   time.AfterFunc,
	}
}

// Notify records that something changed and schedules a push run.
func (n *Notifier) Notify() {
	n.mu.Lock()
	defer n.mu.Unlock()
	if n.pending {
		return
	}
	n.pending = true
	wait := n.Debounce
	if sinceLast := n.now().Sub(n.lastRun); sinceLast < n.MinInterval {
		if remaining := n.MinInterval - sinceLast; remaining > wait {
			wait = remaining
		}
	}
	n.timer = n.afterFunc(wait, n.run)
}

// PushNow runs a push immediately (the admin trigger). It returns the
// counts so the caller can report them.
func (n *Notifier) PushNow(ctx context.Context) (sent, dropped, failed int) {
	n.mu.Lock()
	n.pending = false
	if n.timer != nil {
		n.timer.Stop()
		n.timer = nil
	}
	n.lastRun = n.now()
	n.mu.Unlock()
	return n.push(ctx)
}

func (n *Notifier) run() {
	n.mu.Lock()
	if !n.pending {
		// Cancelled by PushNow after the timer was armed.
		n.mu.Unlock()
		return
	}
	n.pending = false
	n.timer = nil
	n.lastRun = n.now()
	n.mu.Unlock()
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	n.push(ctx)
}

func (n *Notifier) push(ctx context.Context) (sent, dropped, failed int) {
	tokens, err := n.store.ListWidgetPushTokens(ctx)
	if err != nil {
		n.log.Warn("listing tokens", "err", err)
		return 0, 0, 0
	}
	if len(tokens) == 0 {
		return 0, 0, 0
	}
	start := n.now()
	var ok []string
	for _, t := range tokens {
		err := n.sender.Send(ctx, t.Token, t.Environment, ContentChanged)
		switch {
		case err == nil:
			ok = append(ok, t.Token)
			sent++
		case errors.Is(err, ErrBadToken):
			dropped++
			if derr := n.store.DeleteWidgetPushToken(ctx, t.Token); derr != nil {
				n.log.Warn("forgetting rejected token", "err", derr)
			}
		default:
			failed++
			n.log.Warn("widget push failed", "env", t.Environment, "err", err)
		}
	}
	if err := n.store.MarkWidgetPushed(ctx, ok, start); err != nil {
		n.log.Warn("marking pushes", "err", err)
	}
	n.log.Info("widget push", "sent", sent, "dropped", dropped, "failed", failed, "ms", n.now().Sub(start).Milliseconds())
	return sent, dropped, failed
}
