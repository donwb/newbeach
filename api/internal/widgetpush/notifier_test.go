package widgetpush

import (
	"context"
	"errors"
	"sync"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/donwb/beach/api/internal/models"
)

type fakeSender struct {
	mu    sync.Mutex
	sent  []string
	fails map[string]error
}

func (f *fakeSender) Send(_ context.Context, token, _ string, _ []byte) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	if err, ok := f.fails[token]; ok {
		return err
	}
	f.sent = append(f.sent, token)
	return nil
}

type fakeStore struct {
	mu      sync.Mutex
	tokens  []models.WidgetPushToken
	deleted []string
	marked  []string
}

func (s *fakeStore) ListWidgetPushTokens(context.Context) ([]models.WidgetPushToken, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return append([]models.WidgetPushToken(nil), s.tokens...), nil
}
func (s *fakeStore) DeleteWidgetPushToken(_ context.Context, token string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.deleted = append(s.deleted, token)
	return nil
}
func (s *fakeStore) MarkWidgetPushed(_ context.Context, tokens []string, _ time.Time) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.marked = append(s.marked, tokens...)
	return nil
}

// fakeClock drives the notifier's timers by hand.
type fakeClock struct {
	mu  sync.Mutex
	now time.Time
	fns []scheduled
}
type scheduled struct {
	at time.Time
	fn func()
}

func (c *fakeClock) Now() time.Time { c.mu.Lock(); defer c.mu.Unlock(); return c.now }
func (c *fakeClock) AfterFunc(d time.Duration, fn func()) *time.Timer {
	c.mu.Lock()
	c.fns = append(c.fns, scheduled{at: c.now.Add(d), fn: fn})
	c.mu.Unlock()
	return time.NewTimer(time.Hour) // never fires on its own in tests
}

// Advance moves the clock and fires everything due, in order.
func (c *fakeClock) Advance(d time.Duration) {
	c.mu.Lock()
	c.now = c.now.Add(d)
	var due, rest []scheduled
	for _, s := range c.fns {
		if !s.at.After(c.now) {
			due = append(due, s)
		} else {
			rest = append(rest, s)
		}
	}
	c.fns = rest
	c.mu.Unlock()
	for _, s := range due {
		s.fn()
	}
}

func (c *fakeClock) pendingDelay() time.Duration {
	c.mu.Lock()
	defer c.mu.Unlock()
	if len(c.fns) == 0 {
		return -1
	}
	return c.fns[len(c.fns)-1].at.Sub(c.now)
}

func newTestNotifier(sender *fakeSender, store *fakeStore) (*Notifier, *fakeClock) {
	clock := &fakeClock{now: time.Date(2026, 9, 30, 12, 0, 0, 0, time.UTC)}
	n := newNotifier(sender, store)
	n.now = clock.Now
	n.afterFunc = clock.AfterFunc
	return n, clock
}

func TestNotifyDebouncesAFlurryIntoOnePush(t *testing.T) {
	sender := &fakeSender{}
	store := &fakeStore{tokens: []models.WidgetPushToken{{Token: "aa", Environment: "production"}, {Token: "bb", Environment: "sandbox"}}}
	n, clock := newTestNotifier(sender, store)

	n.Notify()
	n.Notify()
	n.Notify()
	assert.Equal(t, n.Debounce, clock.pendingDelay(), "one timer, at the debounce")
	assert.Empty(t, sender.sent, "nothing sent before the debounce")

	clock.Advance(n.Debounce)
	assert.ElementsMatch(t, []string{"aa", "bb"}, sender.sent)
	assert.ElementsMatch(t, []string{"aa", "bb"}, store.marked)
}

func TestNotifyRespectsMinInterval(t *testing.T) {
	sender := &fakeSender{}
	store := &fakeStore{tokens: []models.WidgetPushToken{{Token: "aa", Environment: "production"}}}
	n, clock := newTestNotifier(sender, store)

	n.Notify()
	clock.Advance(n.Debounce)
	require.Len(t, sender.sent, 1)

	// A flip ten seconds after a run waits out the rest of the minute.
	clock.Advance(10 * time.Second)
	n.Notify()
	assert.Equal(t, n.MinInterval-10*time.Second, clock.pendingDelay())
	clock.Advance(n.MinInterval - 10*time.Second)
	assert.Len(t, sender.sent, 2)
}

func TestRejectedTokensAreForgotten(t *testing.T) {
	sender := &fakeSender{fails: map[string]error{
		"gone":  errors.New("wrapped: " + ErrBadToken.Error()),
		"flaky": errors.New("apns: 503"),
	}}
	sender.fails["gone"] = errors.Join(ErrBadToken, errors.New("Unregistered"))
	store := &fakeStore{tokens: []models.WidgetPushToken{
		{Token: "ok", Environment: "production"},
		{Token: "gone", Environment: "production"},
		{Token: "flaky", Environment: "production"},
	}}
	n, _ := newTestNotifier(sender, store)

	sent, dropped, failed := n.PushNow(context.Background())
	assert.Equal(t, 1, sent)
	assert.Equal(t, 1, dropped)
	assert.Equal(t, 1, failed)
	assert.Equal(t, []string{"gone"}, store.deleted)
	assert.Equal(t, []string{"ok"}, store.marked)
}

func TestPushNowCancelsAPendingRun(t *testing.T) {
	sender := &fakeSender{}
	store := &fakeStore{tokens: []models.WidgetPushToken{{Token: "aa", Environment: "production"}}}
	n, clock := newTestNotifier(sender, store)

	n.Notify()
	n.PushNow(context.Background())
	assert.Len(t, sender.sent, 1)
	clock.Advance(n.Debounce)
	assert.Len(t, sender.sent, 1, "the scheduled run was cancelled, not doubled")
}
