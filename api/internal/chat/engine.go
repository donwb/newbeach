// Package chat answers natural-language questions about the beach by
// letting a model choose from a few deterministic tools backed by the
// prediction engine, then relay what the engine said. The model parses the
// question and picks the ramp and the instant; every closure sentence it
// hands back originates in predict's copy, so the chat can never promise
// more than the board does.
package chat

import (
	"context"
	"errors"
	"time"

	"github.com/donwb/beach/api/internal/models"
	"github.com/donwb/beach/api/internal/predict"
)

// ErrWeekendOff is returned by an Engine whose weekend outlook is disabled
// (WEEKEND_OUTLOOK_ENABLED=false); the tool relays it as a plain sentence.
var ErrWeekendOff = errors.New("the weekend outlook is switched off")

// Engine is what the tools read. It is an interface so the tool loop can be
// tested against a fake with a fixed clock and canned answers.
type Engine interface {
	Now() time.Time
	Ramps(ctx context.Context) ([]models.RampStatusWithSince, error)
	OutlookAt(ctx context.Context, accessID string, at time.Time) (*predict.RampOutlookAt, error)
	CityNow(ctx context.Context, city string) (*predict.CityNow, error)
	CityOutlookAt(ctx context.Context, city string, at time.Time) (*predict.CityOutlookAt, error)
	Weekend(ctx context.Context) (*predict.WeekendOutlook, error)
}

type predictEngine struct {
	outlook *predict.Service
	weekend *predict.WeekendService // nil when the feature is off
}

// NewPredictEngine adapts the live prediction services. weekend may be nil.
func NewPredictEngine(outlook *predict.Service, weekend *predict.WeekendService) Engine {
	return &predictEngine{outlook: outlook, weekend: weekend}
}

func (e *predictEngine) Now() time.Time { return time.Now() }

func (e *predictEngine) Ramps(ctx context.Context) ([]models.RampStatusWithSince, error) {
	return e.outlook.Ramps(ctx)
}

func (e *predictEngine) OutlookAt(ctx context.Context, accessID string, at time.Time) (*predict.RampOutlookAt, error) {
	return e.outlook.OutlookAt(ctx, accessID, at)
}

func (e *predictEngine) CityNow(ctx context.Context, city string) (*predict.CityNow, error) {
	return e.outlook.CityNow(ctx, city)
}

func (e *predictEngine) CityOutlookAt(ctx context.Context, city string, at time.Time) (*predict.CityOutlookAt, error) {
	return e.outlook.CityOutlookAt(ctx, city, at)
}

func (e *predictEngine) Weekend(ctx context.Context) (*predict.WeekendOutlook, error) {
	if e.weekend == nil {
		return nil, ErrWeekendOff
	}
	return e.weekend.Get(ctx)
}
