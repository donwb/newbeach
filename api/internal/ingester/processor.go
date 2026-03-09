package ingester

import (
	"context"
	"fmt"

	"github.com/donwb/beach/api/internal/database"
	"github.com/donwb/beach/api/internal/models"
)

// processFeatures upserts each GIS feature into the database and records
// status changes in the history table.
func (ing *Ingester) processFeatures(ctx context.Context, features []gisFeature) error {
	for _, f := range features {
		ramp := models.RampStatus{
			RampName:       f.Attributes.AccessName,
			AccessStatus:   f.Attributes.AccessStatus,
			StatusCategory: models.StatusToCategory(f.Attributes.AccessStatus),
			ObjectID:       f.Attributes.ObjectID,
			City:           f.Attributes.City,
			AccessID:       f.Attributes.AccessID,
			Location:       f.Attributes.GeneralLoc,
		}

		// Check current status to detect changes.
		existing, err := database.GetRampByAccessID(ctx, ing.pool, ramp.AccessID)
		if err != nil {
			return fmt.Errorf("checking existing ramp %s: %w", ramp.AccessID, err)
		}

		statusChanged := existing == nil || existing.AccessStatus != ramp.AccessStatus

		// Upsert the ramp status.
		if err := database.UpsertRampStatus(ctx, ing.pool, ramp); err != nil {
			return fmt.Errorf("upserting ramp %s: %w", ramp.AccessID, err)
		}

		// Record in history if status changed.
		if statusChanged {
			if err := database.InsertRampHistory(ctx, ing.pool, ramp.AccessID, ramp.AccessStatus); err != nil {
				return fmt.Errorf("recording history for ramp %s: %w", ramp.AccessID, err)
			}
			ing.logger.Info("ramp status changed",
				"access_id", ramp.AccessID,
				"ramp_name", ramp.RampName,
				"new_status", ramp.AccessStatus,
			)
		}
	}

	return nil
}
