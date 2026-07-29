package tag

import (
	"context"
	"fmt"
	"strings"

	"github.com/jinzhu/copier"
	"primetime.tools/server/auth"
	"primetime.tools/server/generated/gqlmodel"
	"primetime.tools/server/model"
)

// UpdateTag updates a tag.
func (r *ResolverForTag) UpdateLabelDefinition(ctx context.Context, key string, newKey *string, color string) (*gqlmodel.LabelDefinition, error) {
	tag := model.TagDefinition{}
	userID := auth.GetUser(ctx).ID
	if r.DB.Where(&model.TagDefinition{UserID: userID, Key: key}).Find(&tag).RecordNotFound() {
		return nil, fmt.Errorf("tag with key '%s' does not exist", key)
	}

	tx := r.DB.Begin()

	newValue := model.TagDefinition{
		Key:          strings.ToLower(key),
		Color:        color,
		UserID:       userID,
		UpdatedAtUTC: syncNow(),
	}

	if newKey != nil && *newKey != key {
		if strings.Contains(*newKey, " ") {
			tx.Rollback()
			return nil, fmt.Errorf("tag must not contain spaces")
		}
		*newKey = strings.ToLower(*newKey)
		newValue.Key = *newKey
		timeSpansIdsOfUser := tx.Model(new(model.TimeSpan)).
			Select("id").
			Where(&model.TimeSpan{UserID: userID}).
			SubQuery()

		if err := tx.
			Model(new(model.TimeSpanTag)).
			Where("time_span_id in ?", timeSpansIdsOfUser).
			Where(&model.TimeSpanTag{Key: key}).
			Updates(&model.TimeSpanTag{Key: *newKey}).Error; err != nil {
			tx.Rollback()
			return nil, err
		}
		if err := tx.Model(new(model.LabelValueColor)).
			Where("user_id = ? AND key = ?", userID, key).
			Updates(map[string]interface{}{
				"key":            *newKey,
				"updated_at_utc": newValue.UpdatedAtUTC,
			}).Error; err != nil {
			tx.Rollback()
			return nil, err
		}
		// The rename rewrote labels on timespans; bump their sync timestamp
		// so the rewrite reaches syncing devices.
		if err := tx.Model(new(model.TimeSpan)).
			Where("user_id = ?", userID).
			Where("id IN (SELECT time_span_id FROM time_span_tags WHERE key = ?)", *newKey).
			Update("updated_at_utc", newValue.UpdatedAtUTC).Error; err != nil {
			tx.Rollback()
			return nil, err
		}
	}

	if err := tx.Model(new(model.TagDefinition)).Where(&model.TagDefinition{UserID: userID, Key: key}).Updates(&newValue).Error; err != nil {
		tx.Rollback()
		return nil, err
	}

	if err := tx.Commit().Error; err != nil {
		return nil, err
	}

	gqlTag := &gqlmodel.LabelDefinition{}
	copier.Copy(gqlTag, &newValue)
	gqlTag.UpdatedAt = model.Time(newValue.UpdatedAtUTC)
	colors, err := valueColors(r.DB, userID, newValue.Key)
	if err != nil {
		return nil, err
	}
	gqlTag.ValueColors = colors
	return gqlTag, nil
}
