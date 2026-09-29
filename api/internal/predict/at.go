package predict

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"strings"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/donwb/beach/api/internal/database"
	"github.com/donwb/beach/api/internal/models"
)

// The "at" path answers one question the board never asks: what does the
// engine say about ONE ramp at a SPECIFIC future instant? It replays the
// same pure BuildOutlook the outlook endpoint serves, with the clock set to
// the instant asked about, so the copy a reader gets back is the copy the
// board would show at that moment — never a second, parallel prediction.
//
// Two facts about the replay matter:
//
//   - The water-level anomaly is read relative to the clock passed in, and
//     it needs a fresh gauge sample (anomalyAt, fresh=true). A clock set to
//     Saturday afternoon has no fresh sample, so the anomaly would silently
//     vanish and the tide would be graded on a different basis than the live
//     outlook. BuildRampOutlookAt therefore adjusts the predictions with the
//     REAL clock first (today's anomaly, decayed per day ahead, exactly as
//     the weekend planner does) and hands BuildOutlook pre-adjusted water.
//   - buildSchedule rolls to the next day once the clock passes the close,
//     so a 9pm instant would come back as "opens around 8am" for the day
//     after. The target day's frame is computed separately and an instant
//     past the close is reported as after_close, replayed from the last
//     minute of that driving day.

// Horizon errors, exported so a caller can turn them into a plain sentence.
var (
	ErrPastTime      = errors.New("that time has already passed; the outlook only looks forward")
	ErrBeyondHorizon = errors.New("that is further out than the tide outlook covers (about a week)")
	ErrUnknownRamp   = errors.New("unknown ramp")
)

// atHorizonDays is how far ahead OutlookAt answers — the weekend planner's
// span, past which NOAA's harmonics are fine but the sea state and the
// county's recent form are not knowable.
const atHorizonDays = 7

// Relation values: where the instant asked about falls against the target
// day's driving hours and, inside them, against the ramp's predicted closure
// window.
const (
	RelationBeforeOpen = "before_open"
	RelationAfterClose = "after_close"
	RelationInside     = "inside"
	RelationBefore     = "before"
	RelationAfter      = "after"
	RelationNone       = "none"
)

// RampOutlookAt is one ramp's engine read for a specific instant. Outlook
// carries the same verbatim copy the board shows; everything else is context
// so a narrator can place the instant against the day without computing
// anything itself.
type RampOutlookAt struct {
	AccessID string    `json:"access_id"`
	Name     string    `json:"name"`
	City     string    `json:"city"`
	At       time.Time `json:"at"`
	AtLabel  string    `json:"at_label"` // "Saturday ~2pm", "today ~2pm"
	DaysOut  int       `json:"days_out"` // 0 today, 1 tomorrow …
	Season   string    `json:"season"`
	Schedule Schedule  `json:"schedule"` // the TARGET day's driving frame

	// Outlook is the engine's row for this ramp with the clock set to At
	// (or to the last minute of the driving day when At is after the close).
	Outlook RampOutlook `json:"outlook"`

	// Relation places At against the day: before_open / after_close, or
	// inside / before / after the ramp's predicted closure window, none when
	// the engine predicts no window.
	Relation string `json:"target_vs_hours"`

	// Tide is the next high tide after At, NOAA's own predicted height.
	Tide TideContext `json:"tide"`

	// Now is the live row for the same ramp when At is today — what the
	// board shows this minute — so "right now" and "at 2pm" can be told apart.
	Now *RampOutlook `json:"now,omitempty"`

	Surge   *SurgeContext `json:"surge,omitempty"`
	Caveats []string      `json:"caveats,omitempty"`
}

// BuildRampOutlookAt replays the engine for one ramp at instant at. now is
// the real clock (surge decay and the day count); at is the instant asked
// about. The ramp is replayed as OPEN with no status_since — the backtest's
// convention — because its status right now says nothing about a future
// instant. Pure: no I/O.
func BuildRampOutlookAt(now, at time.Time, r models.RampStatusWithSince, params Params, preds []models.TidePrediction, wave *models.WaveSample, levels []models.WaterLevelSample, prior map[string]PriorDay) RampOutlookAt {
	water, surge := params.withSurge(preds, levels, now)

	r.AccessStatus = "OPEN"
	r.StatusSince = nil

	atET := at.In(eastern)
	anchor := time.Date(atET.Year(), atET.Month(), atET.Day(), 7, 0, 0, 0, eastern)
	season, sched := buildSchedule(anchor, params)

	res := RampOutlookAt{
		AccessID: r.AccessID,
		Name:     RampDisplayName(r),
		City:     models.PrettyCityName(r.City),
		At:       at,
		DaysOut:  daysBetweenET(now, at),
		Season:   season,
		Schedule: sched,
		Surge:    surge,
	}
	res.AtLabel = atLabel(res.DaysOut, at)

	// An instant past the close belongs to a day that is over; the story
	// that instant needs is how that day ended, not the next morning.
	clock := at
	if sched.ClosesAt != nil && !at.Before(*sched.ClosesAt) {
		clock = sched.ClosesAt.Add(-time.Minute)
		res.Relation = RelationAfterClose
		res.Caveats = append(res.Caveats, "the instant asked about is after that day's driving ends; the outlook shown is for the end of that driving day")
	}

	out := BuildOutlook(clock, []models.RampStatusWithSince{r}, params, water, wave, nil, prior)
	if len(out.Ramps) == 1 {
		res.Outlook = replayRampOutlook(out.Ramps[0])
	}

	if res.Relation == "" {
		res.Relation = relationTo(at, sched, res.Outlook.Window)
	}

	// NOAA's own numbers for the next high after the instant.
	for i := range preds {
		if preds[i].Type == "H" && preds[i].Time.After(at) && preds[i].Height != nil {
			res.Tide.NextPeakFt = preds[i].Height
			t := preds[i].Time
			res.Tide.NextPeakAt = &t
			break
		}
	}

	if res.DaysOut > 0 {
		res.Caveats = append(res.Caveats, "future day: graded on the tide alone, no live sea state")
		if res.DaysOut > 1 || prior == nil {
			res.Caveats = append(res.Caveats, "no read on the county's recent form this far out")
		}
	}
	if surge == nil && len(levels) > 0 {
		res.Caveats = append(res.Caveats, "water-level gauges stale; assuming normal water")
	}
	return res
}

// replayCopy makes a line written for "now" read right at another instant:
// the live board says "any time now" and "could go any time now" when a
// quoted close has already passed its clock; at a replayed instant that
// is "by then". Applied to every string a replay hands out.
func replayCopy(s string) string {
	s = strings.ReplaceAll(s, " · could go any time now", "")
	s = strings.ReplaceAll(s, "could go any time now", "could go by then")
	s = strings.ReplaceAll(s, "any time now", "by then")
	return s
}

func replayRampOutlook(ro RampOutlook) RampOutlook {
	ro.Headline = replayCopy(ro.Headline)
	ro.Detail = replayCopy(ro.Detail)
	ro.Short = replayCopy(ro.Short)
	return ro
}

// relationTo places at inside the day's frame and the predicted window.
func relationTo(at time.Time, sched Schedule, w *Window) string {
	if sched.OpensAt != nil && at.Before(*sched.OpensAt) {
		return RelationBeforeOpen
	}
	if sched.ClosesAt != nil && !at.Before(*sched.ClosesAt) {
		return RelationAfterClose
	}
	if w == nil {
		return RelationNone
	}
	switch {
	case at.Before(w.Start):
		return RelationBefore
	case at.After(w.End):
		return RelationAfter
	default:
		return RelationInside
	}
}

// daysBetweenET counts Eastern calendar days from now to at (0 = same day).
func daysBetweenET(now, at time.Time) int {
	n := now.In(eastern)
	a := at.In(eastern)
	nd := time.Date(n.Year(), n.Month(), n.Day(), 0, 0, 0, 0, eastern)
	ad := time.Date(a.Year(), a.Month(), a.Day(), 0, 0, 0, 0, eastern)
	return int(ad.Sub(nd).Round(24*time.Hour).Hours() / 24)
}

// atLabel renders the instant in the copy's voice: "today ~2pm",
// "tomorrow ~10am", "Saturday ~2pm".
func atLabel(daysOut int, at time.Time) string {
	clock := "~" + fmtClock(roundNearest30(at))
	switch daysOut {
	case 0:
		return "today " + clock
	case 1:
		return "tomorrow " + clock
	default:
		return at.In(eastern).Weekday().String() + " " + clock
	}
}

// validateHorizon rejects instants the engine cannot honestly speak to:
// anything before today (the outlook only looks forward — history is a
// different question) and anything past atHorizonDays.
func validateHorizon(now, at time.Time) error {
	n := now.In(eastern)
	todayStart := time.Date(n.Year(), n.Month(), n.Day(), 0, 0, 0, 0, eastern)
	if at.Before(todayStart) {
		return ErrPastTime
	}
	if at.After(now.AddDate(0, 0, atHorizonDays)) {
		return ErrBeyondHorizon
	}
	return nil
}

// RampDisplayName prefers the curated short name, then the pretty GIS name,
// then the access id.
func RampDisplayName(r models.RampStatusWithSince) string {
	if r.ShortName != nil && *r.ShortName != "" {
		return *r.ShortName
	}
	if n := models.PrettyRampName(r.RampName); n != "" {
		return n
	}
	return r.AccessID
}

// rampsTTL is how long the ramp roster is reused between reads. Names and
// metadata change on the order of months; the status on each row is not
// what the "at" path reads.
const rampsTTL = 10 * time.Minute

// Ramps returns every ramp with its metadata, cached for rampsTTL.
func (s *Service) Ramps(ctx context.Context) ([]models.RampStatusWithSince, error) {
	s.mu.Lock()
	if s.ramps != nil && time.Since(s.rampsAt) < rampsTTL {
		out := s.ramps
		s.mu.Unlock()
		return out, nil
	}
	s.mu.Unlock()

	ramps, err := database.GetRampsWithStatusSince(ctx, s.pool, "", "")
	if err != nil {
		return nil, fmt.Errorf("loading ramps: %w", err)
	}
	s.mu.Lock()
	s.ramps = ramps
	s.rampsAt = time.Now()
	s.mu.Unlock()
	return ramps, nil
}

// loadParams reads the learned params, falling back to defaults on any
// problem — the same tolerance the outlook build has.
func loadParams(ctx context.Context, pool *pgxpool.Pool, label string) Params {
	params := Params{Default: DefaultParams}
	raw, err := database.GetSetting(ctx, pool, SettingsKey)
	if err != nil {
		slog.Warn(label+": reading params, using defaults", "err", err)
		return params
	}
	if raw == "" {
		return params
	}
	if err := json.Unmarshal([]byte(raw), &params); err != nil {
		slog.Warn(label+": unparseable params, using defaults", "err", err)
		return Params{Default: DefaultParams}
	}
	return params
}

// OutlookAt answers "what does the engine say about this ramp at that
// instant?" for today through atHorizonDays ahead. It gathers the same
// inputs the live outlook uses — tides around the target date, the latest
// sea state, recent gauge water, and (for today only) what the ramp did
// yesterday — and replays the engine with the clock set to at.
func (s *Service) OutlookAt(ctx context.Context, accessID string, at time.Time) (*RampOutlookAt, error) {
	now := time.Now()
	if err := validateHorizon(now, at); err != nil {
		return nil, err
	}

	ramps, err := s.Ramps(ctx)
	if err != nil {
		return nil, err
	}
	var ramp *models.RampStatusWithSince
	for i := range ramps {
		if ramps[i].AccessID == accessID {
			ramp = &ramps[i]
			break
		}
	}
	if ramp == nil {
		return nil, fmt.Errorf("%w: %s", ErrUnknownRamp, accessID)
	}

	params := loadParams(ctx, s.pool, "outlook-at")

	// A day either side of the target: the falling limb behind it for a
	// reopen, the evening highs ahead of it, and yesterday for the prior
	// when the target is today.
	preds, err := s.noaa.FetchTidePredictionsRange(ctx, at.AddDate(0, 0, -1), at.AddDate(0, 0, 1))
	if err != nil {
		return nil, fmt.Errorf("fetching tide predictions: %w", err)
	}

	var wave *models.WaveSample
	if s.station != "" {
		wave, err = database.GetLatestWaveObservation(ctx, s.pool, s.station)
		if err != nil {
			slog.Warn("outlook-at: reading latest wave observation", "err", err)
			wave = nil
		}
	}

	levels := loadRecentLevels(ctx, s.noaa, s.levelStations, "outlook-at")

	daysOut := daysBetweenET(now, at)
	var prior map[string]PriorDay
	if daysOut == 0 && !s.noPersistence {
		water, _ := params.withSurge(preds, levels, now)
		prior = loadPriorDay(ctx, s.pool, now, water, params, "outlook-at")
	}

	res := BuildRampOutlookAt(now, at, *ramp, params, preds, wave, levels, prior)

	if daysOut == 0 {
		if live, err := s.Get(ctx); err == nil {
			for i := range live.Ramps {
				if live.Ramps[i].AccessID == accessID {
					ro := live.Ramps[i]
					res.Now = &ro
					break
				}
			}
		} else {
			slog.Warn("outlook-at: live outlook unavailable", "err", err)
		}
	}
	return &res, nil
}

// ---- City-level reads -----------------------------------------------------
//
// Most questions are not about one ramp: "can I get on the beach in NSB?",
// "are the Daytona ramps open Saturday morning?". These two reads answer
// them the way the board does — the city verdict plus the ramp rows behind
// it — once for right now (live statuses) and once for a future instant
// (the same replay BuildRampOutlookAt does, for every ramp in the city).

// CityRampAt is one ramp's row inside a city read: the engine's copy plus,
// for the live read, the county's posted status.
type CityRampAt struct {
	AccessID    string     `json:"access_id"`
	Name        string     `json:"name"`
	Status      string     `json:"status,omitempty"` // live read only: raw county status
	StatusSince *time.Time `json:"status_since,omitempty"`
	Risk        string     `json:"risk"`
	Reason      string     `json:"reason,omitempty"`
	Headline    string     `json:"headline"`
	Detail      string     `json:"detail,omitempty"`
	Short       string     `json:"short,omitempty"`
	WindowLabel string     `json:"window_label,omitempty"`
	ReopenLabel string     `json:"reopen_label,omitempty"`
	Relation    string     `json:"target_vs_hours,omitempty"`
}

// CityNow is a city right now: the live verdict the board shows, how many
// ramps are open, and each ramp's posted status with its outlook line.
type CityNow struct {
	City        string       `json:"city"`
	DisplayName string       `json:"display_name"`
	Now         time.Time    `json:"now"`
	Season      string       `json:"season"`
	Schedule    Schedule     `json:"schedule"`
	Verdict     *CityVerdict `json:"verdict,omitempty"`
	OpenCount   int          `json:"open_count"`
	RampCount   int          `json:"ramp_count"`
	Ramps       []CityRampAt `json:"ramps"`
	Tide        TideContext  `json:"tide"`
}

// CityOutlookAt is a city at a future instant: the replayed verdict and
// ramp rows, plus counts by risk so a narrator can say "two of five could
// close" without counting.
type CityOutlookAt struct {
	City        string         `json:"city"`
	DisplayName string         `json:"display_name"`
	At          time.Time      `json:"at"`
	AtLabel     string         `json:"at_label"`
	DaysOut     int            `json:"days_out"`
	Season      string         `json:"season"`
	Schedule    Schedule       `json:"schedule"`
	Relation    string         `json:"target_vs_hours"` // before_open / after_close / open_hours
	Verdict     *CityVerdict   `json:"verdict,omitempty"`
	Counts      map[string]int `json:"counts"` // risk → ramps
	RampCount   int            `json:"ramp_count"`
	Ramps       []CityRampAt   `json:"ramps"`
	Tide        TideContext    `json:"tide"`
	Surge       *SurgeContext  `json:"surge,omitempty"`
	Caveats     []string       `json:"caveats,omitempty"`
}

// RelationOpenHours is the city-level relation when the instant falls
// inside driving hours (per-ramp windows differ, so no single inside/before).
const RelationOpenHours = "open_hours"

// ErrUnknownCity is returned for a city key the roster does not have.
var ErrUnknownCity = errors.New("unknown city")

func cityRampRow(r models.RampStatusWithSince, ro RampOutlook) CityRampAt {
	row := CityRampAt{
		AccessID: r.AccessID,
		Name:     RampDisplayName(r),
		Risk:     ro.Risk,
		Reason:   ro.Reason,
		Headline: ro.Headline,
		Detail:   ro.Detail,
		Short:    ro.Short,
	}
	if ro.Window != nil {
		row.WindowLabel = ro.Window.Label
	}
	if ro.Reopen != nil {
		row.ReopenLabel = ro.Reopen.Label
	}
	return row
}

// BuildCityOutlookAt replays the engine for every ramp in a city at instant
// at. ramps must all belong to one city. Same conventions as
// BuildRampOutlookAt: water adjusted at the real clock, ramps replayed OPEN,
// an after-close instant replayed from the last minute of that driving day.
// Pure.
func BuildCityOutlookAt(now, at time.Time, ramps []models.RampStatusWithSince, params Params, preds []models.TidePrediction, wave *models.WaveSample, levels []models.WaterLevelSample, prior map[string]PriorDay) CityOutlookAt {
	water, surge := params.withSurge(preds, levels, now)

	replay := make([]models.RampStatusWithSince, len(ramps))
	for i, r := range ramps {
		r.AccessStatus = "OPEN"
		r.StatusSince = nil
		replay[i] = r
	}

	atET := at.In(eastern)
	anchor := time.Date(atET.Year(), atET.Month(), atET.Day(), 7, 0, 0, 0, eastern)
	season, sched := buildSchedule(anchor, params)

	res := CityOutlookAt{
		At:        at,
		DaysOut:   daysBetweenET(now, at),
		Season:    season,
		Schedule:  sched,
		Counts:    map[string]int{},
		RampCount: len(ramps),
		Surge:     surge,
	}
	if len(ramps) > 0 {
		res.City = ramps[0].City
		res.DisplayName = models.PrettyCityName(ramps[0].City)
	}
	res.AtLabel = atLabel(res.DaysOut, at)

	clock := at
	switch {
	case sched.ClosesAt != nil && !at.Before(*sched.ClosesAt):
		clock = sched.ClosesAt.Add(-time.Minute)
		res.Relation = RelationAfterClose
		res.Caveats = append(res.Caveats, "the instant asked about is after that day's driving ends; the rows show how that driving day ends")
	case sched.OpensAt != nil && at.Before(*sched.OpensAt):
		res.Relation = RelationBeforeOpen
	default:
		res.Relation = RelationOpenHours
	}

	out := BuildOutlook(clock, replay, params, water, wave, nil, prior)
	for i := range out.Ramps {
		row := cityRampRow(replay[i], replayRampOutlook(out.Ramps[i]))
		row.Relation = relationTo(at, sched, out.Ramps[i].Window)
		res.Ramps = append(res.Ramps, row)
		res.Counts[out.Ramps[i].Risk]++
	}
	if len(out.Cities) > 0 {
		cv := out.Cities[0]
		cv.Headline = replayCopy(cv.Headline)
		cv.Detail = replayCopy(cv.Detail)
		res.Verdict = &cv
	}

	for i := range preds {
		if preds[i].Type == "H" && preds[i].Time.After(at) && preds[i].Height != nil {
			res.Tide.NextPeakFt = preds[i].Height
			t := preds[i].Time
			res.Tide.NextPeakAt = &t
			break
		}
	}

	if res.DaysOut > 0 {
		res.Caveats = append(res.Caveats, "future day: graded on the tide alone, no live sea state")
		if res.DaysOut > 1 || prior == nil {
			res.Caveats = append(res.Caveats, "no read on the county's recent form this far out")
		}
		res.Caveats = append(res.Caveats, "the verdict line is written as if standing at that instant; the ramps are assumed open going in")
	}
	if surge == nil && len(levels) > 0 {
		res.Caveats = append(res.Caveats, "water-level gauges stale; assuming normal water")
	}
	return res
}

// cityRamps filters the roster to one GIS city key.
func cityRamps(ramps []models.RampStatusWithSince, city string) []models.RampStatusWithSince {
	var out []models.RampStatusWithSince
	for i := range ramps {
		if ramps[i].City == city {
			out = append(out, ramps[i])
		}
	}
	return out
}

// CityOutlookAt answers "what does the engine say about this city at that
// instant?" — the city-wide counterpart of OutlookAt.
func (s *Service) CityOutlookAt(ctx context.Context, city string, at time.Time) (*CityOutlookAt, error) {
	now := time.Now()
	if err := validateHorizon(now, at); err != nil {
		return nil, err
	}
	ramps, err := s.Ramps(ctx)
	if err != nil {
		return nil, err
	}
	mine := cityRamps(ramps, city)
	if len(mine) == 0 {
		return nil, fmt.Errorf("%w: %s", ErrUnknownCity, city)
	}

	params := loadParams(ctx, s.pool, "city-at")
	preds, err := s.noaa.FetchTidePredictionsRange(ctx, at.AddDate(0, 0, -1), at.AddDate(0, 0, 1))
	if err != nil {
		return nil, fmt.Errorf("fetching tide predictions: %w", err)
	}
	var wave *models.WaveSample
	if s.station != "" {
		if wave, err = database.GetLatestWaveObservation(ctx, s.pool, s.station); err != nil {
			slog.Warn("city-at: reading latest wave observation", "err", err)
			wave = nil
		}
	}
	levels := loadRecentLevels(ctx, s.noaa, s.levelStations, "city-at")

	var prior map[string]PriorDay
	if daysBetweenET(now, at) == 0 && !s.noPersistence {
		water, _ := params.withSurge(preds, levels, now)
		prior = loadPriorDay(ctx, s.pool, now, water, params, "city-at")
	}

	res := BuildCityOutlookAt(now, at, mine, params, preds, wave, levels, prior)
	return &res, nil
}

// CityNow is a city right now: fresh county statuses (not the 10-minute
// roster cache — "is it open right now" deserves the minute's truth) joined
// to the live outlook's verdict and ramp lines.
func (s *Service) CityNow(ctx context.Context, city string) (*CityNow, error) {
	now := time.Now()
	ramps, err := database.GetRampsWithStatusSince(ctx, s.pool, city, "")
	if err != nil {
		return nil, fmt.Errorf("loading ramps: %w", err)
	}
	if len(ramps) == 0 {
		return nil, fmt.Errorf("%w: %s", ErrUnknownCity, city)
	}

	res := CityNow{
		City:        city,
		DisplayName: models.PrettyCityName(city),
		Now:         now,
		RampCount:   len(ramps),
	}

	live, err := s.Get(ctx)
	if err != nil {
		slog.Warn("city-now: live outlook unavailable, statuses only", "err", err)
		live = nil
	}
	byID := map[string]RampOutlook{}
	if live != nil {
		res.Season = live.Season
		res.Schedule = live.Schedule
		res.Tide = live.Tide
		for _, ro := range live.Ramps {
			byID[ro.AccessID] = ro
		}
		for i := range live.Cities {
			if live.Cities[i].City == city {
				cv := live.Cities[i]
				res.Verdict = &cv
				break
			}
		}
	}

	for _, r := range ramps {
		row := cityRampRow(r, byID[r.AccessID])
		row.Status = r.AccessStatus
		row.StatusSince = r.StatusSince
		if strings.EqualFold(strings.TrimSpace(r.AccessStatus), "OPEN") {
			res.OpenCount++
		}
		res.Ramps = append(res.Ramps, row)
	}
	// The verdict's counts come from the cached build; the fresh statuses win.
	if res.Verdict != nil {
		cv := *res.Verdict
		cv.OpenCount = res.OpenCount
		cv.RampCount = res.RampCount
		res.Verdict = &cv
	}
	return &res, nil
}
